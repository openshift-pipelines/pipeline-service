#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -exuo pipefail

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
export KUBECONFIG=$KUBECONFIG
SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null ; pwd)"
PIPELINES_SERVICE_DIR="$(dirname "$SCRIPT_DIR")"
GITOPS_DIR="$(dirname "$SCRIPT_DIR")/gitops"
KUBECONFIG_KCP="$SCRIPT_DIR/work/kubeconfig/admin.kubeconfig"

#create ns, sa, deployment and service resources
#check if namespace and serviceaccount exists; if not, create them

kubectl delete --ignore-not-found namespace ckcp

kubectl apply -k $GITOPS_DIR/ckcp/base/
podname=$(kubectl get pods -n ckcp -l=app='kcp-in-a-pod' -o jsonpath='{.items[0].metadata.name}')

#check if kcp inside pod is running or not
kubectl wait --for=condition=Ready pod/$podname -n ckcp --timeout=300s

#copy the kubeconfig of kcp from inside the pod onto local filesystem
kubectl cp ckcp/$podname:/workspace/.kcp/admin.kubeconfig $KUBECONFIG_KCP

route=$(kubectl get route ckcp -n ckcp -o jsonpath='{.spec.host}')
sed -i "s/localhost:6443/$route:443/g" $KUBECONFIG_KCP

KUBECONFIG=$KUBECONFIG_KCP kubectl config set-cluster admin --insecure-skip-tls-verify=true

#make sure access to kcp-in-a-pod is good
until KUBECONFIG=$KUBECONFIG_KCP kubectl api-resources
do
  sleep 5
  echo "Try again"
done

kubectl create secret generic ckcp-kubeconfig -n ckcp --from-file $KUBECONFIG_KCP

KUBECONFIG=$KUBECONFIG_KCP kubectl create -f $PIPELINES_SERVICE_DIR/workspace.yaml

#test the registration of a Physical Cluster
curl https://raw.githubusercontent.com/kcp-dev/kcp/948dbe9565cc7da439c698875ca1fa78350c4530/contrib/examples/cluster.yaml > cluster.yaml
sed -e 's/^/    /' $KUBECONFIG | cat cluster.yaml - | KUBECONFIG=$KUBECONFIG_KCP kubectl apply -f -

echo "kcp is ready inside a pod and is synced with cluster 'local' and deployment.apps,pods,services and secrets"

#install pipelines/triggers based on args
if [ $# -eq 0 ]; then
  echo "No args passed; exiting now! ckcp is running in a pod"
else
  for arg in "$@"
  do
    if [ $arg == "pipelines" ]; then
      echo "Arg $arg passed. Installing pipelines in ckcp"

      #clean up old pods if any in kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad ns
      KCPNS=$(kubectl get namespace kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad --ignore-not-found);
      if [[ "$KCPNS" ]]; then
        echo "namespace kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad exists";
        kubectl delete pods -l kcp.dev/cluster=local --field-selector=status.phase==Succeeded -n kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad;
      fi;

      KUBECONFIG=$KUBECONFIG_KCP kubectl apply -k $GITOPS_DIR/tekton-pipeline/overlays/patched

      kubectl delete --ignore-not-found namespace pipelines

      echo "creating namespace pipelines"
      kubectl apply -k $GITOPS_DIR/pipelines/base

      kubectl create secret generic ckcp-kubeconfig -n pipelines --from-file $KUBECONFIG_KCP -o yaml

      cplpod=$(kubectl get pods -n pipelines -o jsonpath='{.items[0].metadata.name}')
      kubectl wait --for=condition=Ready pod/$cplpod -n pipelines --timeout=300s
      sleep 30
      #print the pod running pipelines controller
      KUBECONFIG=$KUBECONFIG kubectl get pods -n pipelines

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
      kubectl create secret generic kcp-kubeconfig --from-file=kubeconfig=$KUBECONFIG_KCP --dry-run=client -o yaml | KUBECONFIG=$KUBECONFIG_KCP kubectl apply -f -
      kubectl create secret generic kcp-kubeconfig -n tekton-pipelines --from-file=kubeconfig=$KUBECONFIG_KCP --dry-run=client -o yaml | KUBECONFIG=$KUBECONFIG_KCP kubectl apply -f -

      kubectl delete --ignore-not-found namespace ctriggers
      echo "creating namespace ctriggers";
      kubectl create namespace ctriggers;

      #create secret for ctriggers namespace on the physical cluster so that triggers controller deployment can use it
      kubectl create secret generic ckcp-kubeconfig -n ctriggers --from-file $KUBECONFIG_KCP --dry-run=client -o yaml | kubectl apply -f -
      kubectl apply -f config/triggers-deployment.yaml

      ctrpod=$(kubectl get pods -n ctriggers -o jsonpath='{.items[0].metadata.name}')
      kubectl wait --for=condition=Ready pod/$ctrpod -n ctriggers --timeout=300s

      #print the pod running pipelines controller
      KUBECONFIG=$KUBECONFIG kubectl get pods -n ctriggers

      KUBECONFIG=$KUBECONFIG_KCP kubectl apply $(ls triggers/config/300-* | awk ' { print " -f " $1 } ')
      KUBECONFIG=$KUBECONFIG_KCP kubectl apply $(ls triggers/config/config-* | awk ' { print " -f " $1 } ')

      (cd triggers && KUBECONFIG=../$KUBECONFIG_KCP ko apply -f config/interceptors)

      echo "kubectl get namespaces | grep -i kcp"
      KUBECONFIG=$KUBECONFIG kubectl get namespaces | grep -i kcp

      KUBECONFIG=$KUBECONFIG_KCP kubectl apply -f triggers/examples/v1beta1/github/

      echo "Print Interceptor and Event Listener resources in the physical cluster"
      KUBECONFIG=$KUBECONFIG kubectl -n kcpa9f18e6516b976c21e45eb38fd4291927a3c9dd86fda1b7b7c03ead1 get deploy,pods
      KUBECONFIG=$KUBECONFIG kubectl -n kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad get deploy,pods

    else
      echo "Incorrect argument/s passed. Allowed args are 'pipelines' or 'pipelines triggers'"
    fi
  done
fi

