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
sed -i "s/\[::1]/$external_ip/g" kubeconfig/admin.kubeconfig

#make sure access to kcp-in-a-pod is good
until KUBECONFIG=kubeconfig/admin.kubeconfig kubectl api-resources
do
  sleep 5
  echo "Try again"
done

kubectl create secret generic ckcp-kubeconfig -n ckcp --from-file kubeconfig/admin.kubeconfig

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
      if [[ ! -d ./pipeline ]]
      then
        git clone git@github.com:tektoncd/pipeline.git
        (cd ./pipeline && git checkout v0.32.0)

        # This feature unblocks Tekton pods. The READY annotation is not correctly propagated to the physical cluster.
        (cd pipeline && git apply ../../pipeline-ff.patch)

        # Conversion is not working yet on KCP
        (cd pipeline && git apply ../../remove-conversion.patch)
      fi

      #clean up old pods if any in kcp--admin--default ns
      KCPNS=$(kubectl get namespace kcp--admin--default --ignore-not-found);
      if [[ "$KCPNS" ]]; then
        echo "namespace kcp--admin--default exists";
        kubectl delete pods -l kcp.dev/cluster=local --field-selector=status.phase==Succeeded -n kcp--admin--default;
      fi;

      #install namespaces in ckcp
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl create namespace default
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl create namespace tekton-pipelines

      #install pipelines CRDs in ckcp
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply -f pipeline/config/300-pipelinerun.yaml
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply -f pipeline/config/300-taskrun.yaml

      # will go away with v1 graduation
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply -f pipeline/config/300-run.yaml
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply -f pipeline/config/300-resource.yaml
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply -f pipeline/config/300-condition.yaml

      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply $(ls pipeline/config/config-* | awk ' { print " -f " $1 } ')

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
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl create -f pipeline/examples/v1beta1/taskruns/custom-env.yaml
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl create -f pipeline/examples/v1beta1/pipelineruns/using_context_variables.yaml

      sleep 20
      echo "Print kube resources inside kcp"
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl get pods,taskruns,pipelineruns
      echo "Print kube resources in the physical cluster (Note: physical cluster will not know what taskruns or pipelinesruns are)"
      KUBECONFIG=$KUBECONFIG kubectl get pods -n kcp--admin--default

      #removing pipelines folder created at the start of the script
      rm -rf pipeline

    elif [ $arg == "triggers" ]; then
        echo "Arg triggers passed. Installing triggers in ckcp (yet to implement)"
    else
      echo "Incorrect argument/s passed. Allowed args are 'pipelines' or 'triggers' or 'pipelines triggers'"
    fi
  done
fi

