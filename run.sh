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
  (cd pipeline && git apply ../../label.patch)
  (cd pipeline && git apply ../../pipeline-ff.patch)
fi

if [[ ! -f ./kcp/bin/kcp ]]
then
  (cd ./kcp && mkdir -p bin/ && go build -ldflags "-X k8s.io/component-base/version.gitVersion=v1.22.2 -X k8s.io/component-base/version.gitCommit=5e58841cce77d4bc13713ad2b91fa0d961e69192" -o bin/kcp ./cmd/kcp)
fi
if [[ ! -f ./pipeline/bin/controller ]]
then
  (cd ./pipeline && make bin/controller)
fi

# Start KCP
rm -rf .kcp/

./kcp/bin/kcp start \
  --push_mode=true \
  --pull_mode=false \
  --install_cluster_controller \
  --install_workspace_controller \
  --auto_publish_apis \
   --resources_to_sync="deployments.apps,pods" &
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

# Test 1 - start a webserver

kubectl create namespace default
kubectl create deployment nginx --image=nginx
kubectl label deploy nginx kcp.dev/cluster=local

# Test 2 - install Tekton CRDs

#kubectl apply -f pipeline/config/300-pipelinerun.yaml
#kubectl apply -f pipeline/config/300-taskrun.yaml
kubectl apply $(ls pipeline/config/300-* | awk ' { print " -f " $1 } ')
kubectl apply $(ls pipeline/config/config-* | awk ' { print " -f " $1 } ')

# Test 3 - create taskrun and pipelinerun

kubectl create serviceaccount default
kubectl create -f pipeline/examples/v1beta1/taskruns/custom-env.yaml
kubectl create -f pipeline/examples/v1beta1/pipelineruns/using_context_variables.yaml

METRICS_DOMAIN=knative.dev/some-repository SYSTEM_NAMESPACE=tekton-pipelines KO_DATA_PATH=./pipeline/pkg/pod/testdata ./pipeline/bin/controller \
  -kubeconfig-writer-image quay.io/openshift-pipeline/openshift-pipelines-pipelines-kubeconfigwriter-rhel8@sha256:f26b87908d90d9b4476a0a0c48e39b5aedb8b9d642f32b2b2c5c9d3649d3b251 \
  -git-image quay.io/openshift-pipeline/openshift-pipelines-pipelines-git-init-rhel8@sha256:c0f011b24f4e659714cae0bdec6286e72aa6a0d36eca2227f0c1074dd791b3ce \
  -entrypoint-image quay.io/openshift-pipeline/openshift-pipelines-pipelines-entrypoint-rhel8@sha256:b6758f84914dd1fa86282d71364a90bc6ec4e2039f261cc73215bb69f35c7e1b \
  -nop-image quay.io/openshift-pipeline/openshift-pipelines-pipelines-nop-rhel8@sha256:3465b61ae753a4090488521ef57df070d34e4c147c73d007927cde8b6ae3a7e6 \
  -imagedigest-exporter-image quay.io/openshift-pipeline/openshift-pipelines-pipelines-imagedigestexporter-rhel8@sha256:3ea6691fdc1fe8d8f778d6f4ed97e8e182bfb7716fa09cf515994a8f11518dec \
  -pr-image quay.io/openshift-pipeline/openshift-pipelines-pipelines-pullrequest-init-rhel8@sha256:f4e56fee435532d21d11901021480f5df66bc751eee260dc40a0003ec1505203 \
  -gsutil-image gcr.io/google.com/cloudsdktool/cloud-sdk@sha256:27b2c22bf259d9bc1a291e99c63791ba0c27a04d2db0a43241ba0f1f20f4067f \
  -shell-image registry.access.redhat.com/ubi8/ubi-minimal@sha256:54ef2173bba7384dc7609e8affbae1c36f8a3ec137cacc0866116d65dd4b9afe \
  -shell-image-win mcr.microsoft.com/powershell:nanoserver@sha256:b6d5ff841b78bdf2dfed7550000fd4f3437385b8fa686ec0f010be24777654d6 &
CONTROLLER_PID=$!

sleep 120

kubectl get pods,taskruns,pipelineruns

kill $CONTROLLER_PID
kill $KCP_PID
