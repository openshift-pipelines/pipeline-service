#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -exuo pipefail

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
export KUBECONFIG=$KUBECONFIG

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
kubectl wait --for=condition=Ready pod/$podname -n ckcp --timeout=300s

#copy the kubeconfig of kcp from inside the pod onto local filesystem
kubectl cp ckcp/$podname:/workspace/.kcp/admin.kubeconfig kubeconfig/admin.kubeconfig

#check if external ip is assigned and replace kcp's external IP in the kubeconfig file
while [ "$(kubectl get service ckcp-service -n ckcp -o jsonpath='{.status.loadBalancer.ingress[0]}')" == "" ]; do
  sleep 3
  echo "Waiting for external ip or hostname to be assigned"
done

sleep 60

external_ip=$(kubectl get service ckcp-service -n ckcp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
external_ip+=$(kubectl get service ckcp-service -n ckcp -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
sed -i "s/\[::1]/$external_ip/g" kubeconfig/admin.kubeconfig

sleep 10

#make sure access to kcp-in-a-pod is good
KUBECONFIG=kubeconfig/admin.kubeconfig kubectl api-resources

#test the registration of a Physical Cluster
curl https://raw.githubusercontent.com/kcp-dev/kcp/main/contrib/examples/cluster.yaml > cluster.yaml
sed -e 's/^/    /' $KUBECONFIG | cat cluster.yaml - | KUBECONFIG=kubeconfig/admin.kubeconfig kubectl apply -f -


#install pipelines/triggers based on args
if [ $# -eq 0 ]; then
  echo "No args passed; exiting now! ckcp is running in a pod"
else
  for arg in "$@"
  do
    if [ $arg == "pipelines" ]; then
      echo "Arg $arg passed. Installing pipelines in ckcp"
      WORKING_DIR=work/
      mkdir -p $WORKING_DIR
      cd $WORKING_DIR

      if [[ ! -d ./pipeline ]]
      then
        git clone git@github.com:tektoncd/pipeline.git
        (cd ./pipeline && git checkout v0.32.0)

        # Pods need to be placed on a physical cluster
        # Adding the label manually for that purpose.
        (cd pipeline && git apply ../../../label.patch)

        # This feature unblocks Tekton pods. The READY annotation is not correctly propagated to the physical cluster.
        (cd pipeline && git apply ../../../pipeline-ff.patch)

        # Conversion is not working yet on KCP
        (cd pipeline && git apply ../../../remove-conversion.patch)
      fi

      if [[ ! -f ./pipeline/bin/controller ]]
      then
        (cd ./pipeline && make bin/controller)
      fi

      #install namespaces in ckcp
      KUBECONFIG=../kubeconfig/admin.kubeconfig kubectl create namespace default
      KUBECONFIG=../kubeconfig/admin.kubeconfig kubectl create namespace tekton-pipelines

      #install pipelines CRDs in ckcp
      KUBECONFIG=../kubeconfig/admin.kubeconfig kubectl apply -f pipeline/config/300-pipelinerun.yaml
      KUBECONFIG=../kubeconfig/admin.kubeconfig kubectl apply -f pipeline/config/300-taskrun.yaml

      # will go away with v1 graduation
      KUBECONFIG=../kubeconfig/admin.kubeconfig kubectl apply -f pipeline/config/300-run.yaml
      KUBECONFIG=../kubeconfig/admin.kubeconfig kubectl apply -f pipeline/config/300-resource.yaml
      KUBECONFIG=../kubeconfig/admin.kubeconfig kubectl apply -f pipeline/config/300-condition.yaml

      KUBECONFIG=../kubeconfig/admin.kubeconfig kubectl apply $(ls pipeline/config/config-* | awk ' { print " -f " $1 } ')

      # Test 3 - create taskrun and pipelinerun

      KUBECONFIG=../kubeconfig/admin.kubeconfig kubectl create serviceaccount default
      KUBECONFIG=../kubeconfig/admin.kubeconfig kubectl create -f pipeline/examples/v1beta1/taskruns/custom-env.yaml
      KUBECONFIG=../kubeconfig/admin.kubeconfig kubectl create -f pipeline/examples/v1beta1/pipelineruns/using_context_variables.yaml

      KUBECONFIG=../kubeconfig/admin.kubeconfig METRICS_DOMAIN=knative.dev/some-repository SYSTEM_NAMESPACE=tekton-pipelines KO_DATA_PATH=./pipeline/pkg/pod/testdata ./pipeline/bin/controller \
        -kubeconfig-writer-image gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/kubeconfigwriter:v0.32.0 \
        -git-image gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/git-init:v0.32.0 \
        -entrypoint-image gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/entrypoint:v0.32.0 \
        -nop-image gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/nop:v0.32.0 \
        -imagedigest-exporter-image gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/imagedigestexporter:v0.32.0 \
        -pr-image gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/pullrequest-init:v0.32.0 \
        -gsutil-image gcr.io/google.com/cloudsdktool/cloud-sdk@sha256:27b2c22bf259d9bc1a291e99c63791ba0c27a04d2db0a43241ba0f1f20f4067f \
        -shell-image registry.access.redhat.com/ubi8/ubi-minimal@sha256:54ef2173bba7384dc7609e8affbae1c36f8a3ec137cacc0866116d65dd4b9afe \
        -shell-image-win mcr.microsoft.com/powershell:nanoserver@sha256:b6d5ff841b78bdf2dfed7550000fd4f3437385b8fa686ec0f010be24777654d6 &
      CONTROLLER_PID=$!

      sleep 120

      #print kube resources inside kcp
      KUBECONFIG=../kubeconfig/admin.kubeconfig kubectl get pods,taskruns,pipelineruns
      #print kube resources in the physical cluster (Note: physical cluster will not know what taskruns or pipelinesruns are)
      KUBECONFIG=$KUBECONFIG kubectl get pods

      sleep 10

      #kills the pipeline controller before the script is exiting. Comment this line if you want to interact with pipelines after the script exits.
      kill $CONTROLLER_PID

    elif [ $arg == "triggers" ]; then
        echo "Arg triggers passed. Installing triggers in ckcp (yet to implement)"
    else
      echo "Incorrect argument/s passed. Allowed args are 'pipelines' or 'triggers' or 'pipelines triggers'"
    fi
  done
fi

