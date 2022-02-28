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
      if [[ ! -d ./pipeline ]]
      then
        git clone git@github.com:tektoncd/pipeline.git
        (cd ./pipeline && git checkout v0.32.0)

        # Conversion is not working yet on KCP
        (cd pipeline && git apply ../../remove-conversion.patch)
      fi

      #clean up old pods if any in kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad ns
      KCPNS=$(kubectl get namespace kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad --ignore-not-found);
      if [[ "$KCPNS" ]]; then
        echo "namespace kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad exists";
        kubectl delete pods -l kcp.dev/cluster=local --field-selector=status.phase==Succeeded -n kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad;
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
      KUBECONFIG=$KUBECONFIG kubectl get pods -n kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad

    elif [ $arg == "triggers" ]; then
      echo "Arg triggers passed. Installing triggers in ckcp"

      if [[ ! -d ./triggers ]]
      then
      git clone git@github.com:tektoncd/triggers.git
      (cd ./triggers && git checkout 7fbff3b122fcb77d44e1b39bb45c8a935e61f5ed)

      # Deployments need to talk to core interceptors. KCP rewrites namespace in physical cluster,
      # so we have to patch it until we get proper communication
      (cd triggers && git apply ../../sink.patch)

      # EventListeners and interceptors are running on the physical cluster and need access to the KCP API.
      # A special secret is manually created in the physical cluster for that purpose.
      # The deployment is changed to use this secret instead of a service account.
      (cd triggers && git apply ../../triggers-deploy.patch)
      (cd triggers && git apply ../../fix-interceptors.patch)
      fi

      #create secrets for event listener and interceptors so that they can talk to KCP
      kubectl create secret generic kcp-kubeconfig --from-file=kubeconfig=kubeconfig/admin.kubeconfig --dry-run=client -o yaml | KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply -f -
      kubectl create secret generic kcp-kubeconfig -n tekton-pipelines --from-file=kubeconfig=kubeconfig/admin.kubeconfig --dry-run=client -o yaml | KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply -f -

      kubectl delete namespace ctriggers || true;
      echo "creating namespace ctriggers";
      kubectl create namespace ctriggers;

      #create secret for ctriggers namespace on the physical cluster so that triggers controller deployment can use it
      kubectl create secret generic ckcp-kubeconfig -n ctriggers --from-file kubeconfig/admin.kubeconfig --dry-run=client -o yaml | kubectl apply -f -
      kubectl apply -f config/triggers-deployment.yaml

      ctrpod=$(kubectl get pods -n ctriggers -o jsonpath='{.items[0].metadata.name}')
      kubectl wait --for=condition=Ready pod/$ctrpod -n ctriggers --timeout=300s

      #print the pod running pipelines controller
      KUBECONFIG=$KUBECONFIG kubectl get pods -n ctriggers

      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply $(ls triggers/config/300-* | awk ' { print " -f " $1 } ')
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply $(ls triggers/config/config-* | awk ' { print " -f " $1 } ')

      (cd triggers && KUBECONFIG=../kubeconfig/admin.kubeconfig ko apply -f config/interceptors)

      echo "kubectl get namespaces | grep -i kcp"
      KUBECONFIG=$KUBECONFIG kubectl get namespaces | grep -i kcp

      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply -f triggers/examples/v1beta1/github/

      sleep 20
      # Simulate the behaviour of the webhook. GitHub sends some payload and trigger a TaskRun.
      KUBECONFIG=$KUBECONFIG kubectl -n kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad port-forward service/el-github-listener 8089:8080 &
      SVC_FORWARD_PID=$!

      sleep 20
      curl -v \
         -H 'X-GitHub-Event: pull_request' \
         -H 'X-Hub-Signature: sha1=ba0cdc263b3492a74b601d240c27efe81c4720cb' \
         -H 'Content-Type: application/json' \
         -d '{"action": "opened", "pull_request":{"head":{"sha": "28911bbb5a3e2ea034daf1f6be0a822d50e31e73"}},"repository":{"clone_url": "https://github.com/tektoncd/triggers.git"}}' \
         http://localhost:8089
      kill $SVC_FORWARD_PID

      sleep 20
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl get taskruns,pipelineruns

    else
      echo "Incorrect argument/s passed. Allowed args are 'pipelines' or 'pipelines triggers'"
    fi
  done
fi

