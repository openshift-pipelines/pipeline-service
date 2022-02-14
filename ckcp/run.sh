#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -exuo pipefail

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
export KUBECONFIG=$KUBECONFIG

#create ns, sa, deployment and service resources
#check if namespace and serviceaccount exists; if not, create them

kubectl delete namespace ckcp || true;
echo "creating namespace ckcp";
kubectl create namespace ckcp;

SA=$(kubectl get sa anyuid -n ckcp --ignore-not-found);
if [[ "$SA" ]]; then
  echo "service account anyuid already exists in ckcp namespace";
else
  echo "creating service account anyuid in ckcp namespace";
  oc create sa anyuid -n ckcp;
  oc adm policy add-scc-to-user -n ckcp -z anyuid anyuid;
fi;

sed "s|quay.io/bnr|$KO_DOCKER_REPO|g" config/kcp-deployment.yaml | kubectl apply -f -
kubectl apply -f config/kcp-service.yaml

podname=$(kubectl get pods -n ckcp -l=app='kcp-in-a-pod' -o jsonpath='{.items[0].metadata.name}')

#check if kcp inside pod is running or not
kubectl wait --for=condition=Ready pod/$podname -n ckcp --timeout=300s

#copy the kubeconfig of kcp from inside the pod onto local filesystem
rm -f kubeconfig/admin.kubeconfig
kubectl cp ckcp/$podname:/workspace/.kcp/admin.kubeconfig kubeconfig/admin.kubeconfig

#check if external ip is assigned and replace kcp's external IP in the kubeconfig file
while [ "$(kubectl get service ckcp-service -n ckcp -o jsonpath='{.status.loadBalancer.ingress[0]}')" == "" ]; do
  sleep 3
  echo "Waiting for external ip or hostname to be assigned"
done

#sleep 60

external_ip=$(kubectl get service ckcp-service -n ckcp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
external_ip+=$(kubectl get service ckcp-service -n ckcp -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
sed -i "s/localhost/$external_ip/g" kubeconfig/admin.kubeconfig

KUBECONFIG=kubeconfig/admin.kubeconfig kubectl config set-cluster admin --insecure-skip-tls-verify=true

#make sure access to kcp-in-a-pod is good
until KUBECONFIG=kubeconfig/admin.kubeconfig kubectl api-resources
do
  sleep 5
  echo "Try again"
done

kubectl create secret generic ckcp-kubeconfig -n ckcp --from-file kubeconfig/admin.kubeconfig

KUBECONFIG=kubeconfig/admin.kubeconfig kubectl create -f ../workspace.yaml

#test the registration of a Physical Cluster
curl https://raw.githubusercontent.com/kcp-dev/kcp/main/contrib/examples/cluster.yaml > cluster.yaml
sed -e 's/^/    /' $KUBECONFIG | cat cluster.yaml - | KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply -f -

echo "kcp is ready inside a pod and is synced with cluster 'local' and deployment.apps,pods,services and secrets"

#install pipelines/triggers based on args
if [ $# -eq 0 ]; then
  echo "No args passed; exiting now! ckcp is running in a pod"
else
  for arg in "$@"
  do
    if [ $arg == "pipelines" ]; then
      echo "Arg $arg passed. Installing pipelines in ckcp"

      #clean up old pods if any in kcp--admin--default ns
      KCPNS=$(kubectl get namespace kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad --ignore-not-found);
      if [[ "$KCPNS" ]]; then
        echo "namespace kcp--admin--default exists";
        kubectl delete pods -l kcp.dev/cluster=local --field-selector=status.phase==Succeeded -n kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad;
      fi;

      PIPELINES="https://raw.githubusercontent.com/tektoncd/pipeline/v0.32.0"
      CONFIG="$PIPELINES/config"

      #install namespaces in ckcp
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl create namespace default
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl create namespace tekton-pipelines

      #install pipelines CRDs in ckcp
      curl -L "$CONFIG/300-pipelinerun.yaml" \
        | yq e 'del(.spec.conversion)' - \
        | KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply -f -
      curl -L "$CONFIG/300-taskrun.yaml" \
        | yq e 'del(.spec.conversion)' - \
        | KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply -f -

      # will go away with v1 graduation
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply -f "$CONFIG/300-run.yaml" \
        -f "$CONFIG/300-resource.yaml" \
        -f "$CONFIG/300-condition.yaml"

      curl -L "$CONFIG/config-feature-flags.yaml" \
        | yq eval '.data.running-in-environment-with-injected-sidecars = false' - \
        | KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply -f -

      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply \
        -f "$CONFIG/config-artifact-bucket.yaml" \
        -f "$CONFIG/config-artifact-pvc.yaml" \
        -f "$CONFIG/config-defaults.yaml" \
        -f "$CONFIG/config-info.yaml" \
        -f "$CONFIG/config-leader-election.yaml" \
        -f "$CONFIG/config-logging.yaml" \
        -f "$CONFIG/config-observability.yaml" \
        -f "$CONFIG/config-registry-cert.yaml"

      kubectl delete namespace cpipelines || true;

      echo "creating namespace cpipelines";
      kubectl create namespace cpipelines;

      kubectl create secret generic ckcp-kubeconfig -n cpipelines --from-file kubeconfig/admin.kubeconfig -o yaml
      kubectl apply -f config/pipelines-deployment.yaml

      cplpod=$(kubectl get pods -n cpipelines -o jsonpath='{.items[0].metadata.name}')
      kubectl wait --for=condition=Ready pod/$cplpod -n cpipelines --timeout=300s
      sleep 30
      #print the pod running pipelines controller
      KUBECONFIG=$KUBECONFIG kubectl get pods -n cpipelines

      #create taskrun and pipelinerun
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl create serviceaccount default
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl create -f "$PIPELINES/examples/v1beta1/taskruns/custom-env.yaml"
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl create -f "$PIPELINES/examples/v1beta1/pipelineruns/using_context_variables.yaml"

      sleep 20
      echo "Print kube resources inside kcp"
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl get pods,taskruns,pipelineruns
      echo "Print kube resources in the physical cluster (Note: physical cluster will not know what taskruns or pipelinesruns are)"
      KUBECONFIG=$KUBECONFIG kubectl get pods -n kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad
    elif [ $arg == "triggers" ]; then
        echo "Arg triggers passed. Installing triggers in ckcp (yet to implement)"
    else
      echo "Incorrect argument/s passed. Allowed args are 'pipelines' or 'triggers' or 'pipelines triggers'"
    fi
  done
fi

