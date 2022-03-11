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

      #TODO : Remove this by shifting this to pipelines
      kubectl create namespace default --dry-run=client -o yaml | KUBECONFIG=$KUBECONFIG_KCP kubectl apply -f -

      #create secrets for event listener and interceptors so that they can talk to KCP; create secrets for triggers controller
      kubectl create secret generic ckcp-kubeconfig -n ctriggers --from-file kubeconfig/admin.kubeconfig --dry-run=client -o yaml | kubectl apply -f -
      kubectl create secret generic kcp-kubeconfig --from-file=kubeconfig=$KUBECONFIG_KCP --dry-run=client -o yaml | KUBECONFIG=$KUBECONFIG_KCP kubectl apply -f -
      kubectl create secret generic kcp-kubeconfig -n tekton-pipelines --from-file=kubeconfig=$KUBECONFIG_KCP --dry-run=client -o yaml | KUBECONFIG=$KUBECONFIG_KCP kubectl apply -f -

      #create everything using kustomize
      #Deploy triggers controller
      kubectl apply -k $GITOPS_DIR/triggers/triggers-controller/base

      #Check if triggers controller pod is up and running
      ctrpod=$(kubectl get pods -n triggers -o jsonpath='{.items[0].metadata.name}')
      kubectl wait --for=condition=Ready pod/$ctrpod -n triggers --timeout=300s
      KUBECONFIG=$KUBECONFIG kubectl get pods -n triggers

      #Apply triggers crds (300-* & config-*)
      KUBECONFIG=$KUBECONFIG_KCP kubectl apply -k $GITOPS_DIR/triggers/triggers-crds/base

      sleep 30
      #Deploy triggers interceptors
      KUBECONFIG=$KUBECONFIG_KCP kubectl apply -k $GITOPS_DIR/triggers/triggers-crds/interceptors

    else
      echo "Incorrect argument/s passed. Allowed args are 'pipelines' or 'pipelines triggers'"
    fi
  done
fi

