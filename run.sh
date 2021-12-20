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
  (cd ./kcp && git checkout ae4e07fcd4399264dccab47509ef17f2851050ee)
fi
if [[ ! -d ./pipeline ]]
then
  git clone git@github.com:tektoncd/pipeline.git
  (cd ./pipeline && git checkout b47e0797bb549cac465cbedb2783c1ac5234d69b)

  # Pods need to be placed on a physical cluster
  # Adding the label manually for that purpose.
  (cd pipeline && git apply ../../label.patch)

  # This feature unblocks Tekton pods. The READY annotation is not correctly propagated to the physical cluster.
  (cd pipeline && git apply ../../pipeline-ff.patch)

  # Conversion is not working yet on KCP
  (cd pipeline && git apply ../../remove-conversion.patch)
fi
if [[ ! -d ./triggers ]]
then
  git clone git@github.com:tektoncd/triggers.git

  # Deployments and services need to be placed on a physical cluster
  # Adding the label manually for that purpose.
  (cd triggers && git apply ../../triggers-label.patch)

  # EventListeners are running on the physical cluster and need access to the KCP API.
  # A special secret is manually created in the physical cluster for that purpose.
  # The deployment is changed to use this secret instead of a service account.
  (cd triggers && git apply ../../triggers-deploy.patch)

  # Interceptors are not working yet - removing it from the example for the moment.
  (cd triggers && git apply ../../remove-interceptor.patch)
fi

if [[ ! -f ./kcp/bin/kcp ]]
then
  (cd ./kcp && mkdir -p bin/ && go build -ldflags "-X k8s.io/component-base/version.gitVersion=v1.22.2 -X k8s.io/component-base/version.gitCommit=5e58841cce77d4bc13713ad2b91fa0d961e69192" -o bin/kcp ./cmd/kcp)
fi
if [[ ! -f ./pipeline/bin/controller ]]
then
  (cd ./pipeline && make bin/controller)
fi
if [[ ! -f ./triggers/bin/controller ]]
then
  (cd ./triggers && mkdir -p bin/ && go build -o bin/controller ./cmd/controller)
fi

# Start KCP
rm -rf .kcp/

./kcp/bin/kcp start \
  --push-mode=true \
  --pull-mode=false \
  --install-cluster-controller \
  --install-workspace-controller \
  --auto-publish-apis \
  --resources-to-sync="deployments.apps,pods,services" &
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

# Test 4 - install triggers

kubectl apply $(ls triggers/config/300-* | awk ' { print " -f " $1 } ')
kubectl apply $(ls triggers/config/config-* | awk ' { print " -f " $1 } ')

kubectl apply -f triggers/examples/v1beta1/github/

# Add a secret in the physical cluster so that the event listener can query KCP API
cp ./.kcp/admin.kubeconfig ./.kcp/remote.kubeconfig
gsed -i "s/\[::1\]/host.docker.internal/" ./.kcp/remote.kubeconfig
KUBECONFIG=kind1 kubectl create secret generic kcp-kubeconfig --from-file=kubeconfig=./.kcp/remote.kubeconfig

METRICS_PROMETHEUS_PORT=8010 PROFILING_PORT=8009 METRICS_DOMAIN=knative.dev/some-repository SYSTEM_NAMESPACE=tekton-pipelines ./triggers/bin/controller -logtostderr \
  -stderrthreshold 2 \
  -el-image quay.io/gurose/eventlistenersink-7ad1faa98cddbcb0c24990303b220bb8:latest \
  -el-port 8080 \
  -el-security-context=false \
  -el-readtimeout 5 \
  -el-writetimeout 40 \
  -el-idletimeout 120 \
  -el-timeouthandler 30 \
  -period-seconds 10 \
  -failure-threshold 1 &
TRIGGERS_PID=$!

sleep 30

# Simulate the behaviour of the webhook. GitHub sends some payload and trigger a TaskRun.
KUBECONFIG=kind1 kubectl port-forward service/el-github-listener 8089:8080 &
FORWARD_PID=$!

sleep 30

curl -v \
   -H 'X-GitHub-Event: pull_request' \
   -H 'X-Hub-Signature: sha1=ba0cdc263b3492a74b601d240c27efe81c4720cb' \
   -H 'Content-Type: application/json' \
   -d '{"action": "opened", "pull_request":{"head":{"sha": "28911bbb5a3e2ea034daf1f6be0a822d50e31e73"}},"repository":{"clone_url": "https://github.com/tektoncd/triggers.git"}}' \
   http://localhost:8089
kill $FORWARD_PID

sleep 30

kubectl get taskruns,pipelineruns
KUBECONFIG=kind1 kubectl get pods

kill $CONTROLLER_PID
kill $TRIGGERS_PID
kill $KCP_PID
