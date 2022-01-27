#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -exuo pipefail

#create ns, sa, deployment and service resources
#check if namespace and serviceaccount exists; if not, create them
NS=$(kubectl get namespace ckcp --ignore-not-found);
if [[ "$NS" ]]; then
  echo "namespace ckcp exists";
  kubectl delete all --all -n ckcp;
  kubectl delete ns ckcp;
  kubectl create namespace ckcp;
else
  echo "creating namespace ckcp";
  kubectl create namespace ckcp;
fi;
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
kubectl wait --for=condition=Ready pod/$podname -n ckcp

#copy the kubeconfig of kcp from inside the pod onto local filesystem
kubectl cp ckcp/$podname:/workspace/.kcp/admin.kubeconfig kubeconfig/admin.kubeconfig

#check if external ip is assigned and replace kcp's external IP in the kubeconfig file
while [ "$(kubectl get service ckcp-service -n ckcp -o jsonpath='{.status.loadBalancer.ingress[0].ip}')" == "" ]; do
  sleep 3
  echo "Waiting for external ip to be assigned"
done
external_ip=$(kubectl get service ckcp-service -n ckcp -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
sed -i "s/\[::1]/$external_ip/g" kubeconfig/admin.kubeconfig

sleep 10

#make sure access to kcp-in-a-pod is good
KUBECONFIG=kubeconfig/admin.kubeconfig kubectl api-resources

#copy the physical cluster's config inside the pod
#kubectl cp $HOME/.kube/config ckcp/$podname:/workspace/cluster1.yaml

#export KUBECONFIG inside the pod & test the registration of a Physical Cluster
#kubectl -n ckcp exec $podname -- bash -c "export KUBECONFIG=/workspace/.kcp/admin.kubeconfig && sed -e 's/^/    /' /workspace/cluster1.yaml | cat ./kcp/contrib/examples/cluster.yaml - | kubectl apply -f -"

#test the registration of a Physical Cluster
export KUBECONFIG=kubeconfig/admin.kubeconfig
sed -e 's/^/    /' $HOME/.kube/config | cat ./kcp/contrib/examples/cluster.yaml - | kubectl apply -f -