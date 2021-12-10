#!/usr/bin/env bash

set -exuo pipefail

# kill all the child processes for this script when it exits
trap 'jobs=($(jobs -p)); [ -n "${jobs-}" ] && ((${#jobs})) && kill "${jobs[@]}" || true' EXIT

WORKING_DIR=work/

mkdir -p $WORKING_DIR
cd $WORKING_DIR

# Fetch sources and compile them

if [[ ! -d ./kcp ]]
then
  git clone git@github.com:kcp-dev/kcp.git
fi
if [[ ! -d ./pipeline ]]
then
  git clone git@github.com:tektoncd/pipeline.git
fi

if [[ ! -f ./kcp/bin/kcp ]]
then
  (cd ./kcp && mkdir -p bin/ && go build -ldflags "-X k8s.io/client-go/pkg/version.gitVersion=v1.22.2 -X k8s.io/client-go/pkg/version.gitCommit=5e58841cce77d4bc13713ad2b91fa0d961e69192" -o bin/kcp ./cmd/kcp)
fi

# Start KCP
rm -rf .kcp/

./kcp/bin/kcp start \
  --push_mode=true \
  --pull_mode=false \
  --install_cluster_controller \
  --install_workspace_controller \
  --auto_publish_apis \
   --resources_to_sync="deployments.apps" &
KCP_PID=$!

export KUBECONFIG=.kcp/admin.kubeconfig

# Add one kind cluster

KUBECONFIG=kind1 kind delete cluster
KUBECONFIG=kind1 kind create cluster

sed -e 's/^/    /' kind1 | cat ./kcp/contrib/examples/cluster.yaml - | kubectl apply -f -
sleep 5

# Cluster is added and deployments API is added to KCP automatically
kubectl describe cluster
kubectl api-resources

echo "KCP is ready. You can use it with :"
echo "KUBECONFIG=./work/.kcp/admin.kubeconfig kubectl api-resources"
# Wait a bit

# Test 1 - start a webserver

kubectl create namespace default
kubectl create deployment nginx --image=nginx
kubectl label deploy nginx kcp.dev/cluster=local

# Test 2 - install Tekton CRDs

kubectl apply -f pipeline/config/300-pipelinerun.yaml
kubectl apply -f pipeline/config/300-taskrun.yaml

sleep 3600

kill $KCP_PID
