#!/usr/bin/env bash

# Copyright 2022 The pipelines-service Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

usage() {

    printf "Usage: KUBECONFIG="path-to-kubeconfig" GITOPS_REPO="https://gitops.com/group/project" GIT_TOKEN="XXXXXXXXX" WEBHOOK_SECRET="YYYYYYYYYY" ./setup.sh\n\n"
	
    # Parameters
    printf "The following parameters need to be passed to the script:\n"
    printf "KUBECONFIG: the path to the kubeconfig file used to connect to the cluster where Pipelines as Code will be installed\n"
    printf "GITOPS_REPO: the repository for which Pipelines as Code needs to be set up\n"
    printf "GIT_TOKEN: personal access token to the git repository\n"
    printf "WEBHOOK_SECRET: secret configured on the webhook used to validate the payload\n"
    printf "CONTROLLER_INSTALL (optional): the controller will be installed only if it is set to true. Pipelines as Code are installed together with the OpenShift Pipelines operator\n"
    printf "PAC_HOST (optional): Hostname for the Pipelines as Code ingress if CONTROLLER_INSTALL=true has been set\n\n"
}

check_params() {
    KUBECONFIG="${KUBECONFIG:-}"
    GITOPS_REPO="${GITOPS_REPO:-}"
    GIT_TOKEN="${GIT_TOKEN:-}"
    WEBHOOK_SECRET="${WEBHOOK_SECRET:-}"
    if [[ -z "${KUBECONFIG}" ]]; then
        printf "KUBECONFIG environment variable needs to be set\n\n"
	usage
	exit 1
    fi
    if [[ -z "${GITOPS_REPO}" ]]; then
        printf "GITOPS_REPO environment variable needs to be set\n\n"
	usage
        exit 1
    fi
    if [[ -z "${GIT_TOKEN}" ]]; then
        printf "GIT_TOKEN environment variable needs to be set\n\n"
        usage
        exit 1
    fi
    if [[ -z "${WEBHOOK_SECRET}" ]]; then
        printf "WEBHOOK_SECRET environment variable needs to be set\n\n"
        usage
        exit 1
    fi
}

controller_install() {
    CONTROLLER_INSTALL="${CONTROLLER_INSTALL:-}"
    if [[ $(tr '[:upper:]' '[:lower:]' <<< "$CONTROLLER_INSTALL") == "true" ]]; then
       printf "Installing controller\n"
       kubectl --kubeconfig ${KUBECONFIG} patch tektonconfig config --type="merge" -p '{"spec": {"addon":{"enablePipelinesAsCode": false}}}'
       kubectl --kubeconfig ${KUBECONFIG} apply -f https://github.com/openshift-pipelines/pipelines-as-code/releases/download/0.10.0/release.yaml
    fi
}

mk_tmpdir () {
  TMP_DIR="$(mktemp -d -t pac-pipelines-service.XXXXXXXXX)"
  printf "Temporary directory created: ${TMP_DIR}\n"
}

kustomize () {

    GIT_TOKEN=$(echo "${GIT_TOKEN}" | base64)
    WEBHOOK_SECRET=$(echo "${WEBHOOK_SECRET}" | base64)

    # Create a json patch for the repository
    cat <<EOF > ${TMP_DIR}/patch-repo.yaml
- op: replace
  path: /spec/url
  value: ${GITOPS_REPO}
EOF

    # Create a json patch for the secret
    cat <<EOF > ${TMP_DIR}/patch-secret.yaml
- op: replace
  path: /data/provider.token
  value: ${GIT_TOKEN}
- op: replace
  path: /data/webhook.secret
  value: ${WEBHOOK_SECRET}
EOF

    if [[ $(tr '[:upper:]' '[:lower:]' <<< "$CONTROLLER_INSTALL") == "true" ]]; then
        # Create a json patch for the ingress
        cat <<EOF > ${TMP_DIR}/patch-ingress.yaml
- op: replace
  path: /spec/rules/0/host
  value: ${PAC_HOST}
EOF
        cp $parent_path/manifests/ingress.yaml ${TMP_DIR}/ingress.yaml
        # kustomization.yaml
        cat <<EOF > ${TMP_DIR}/kustomization.yaml
resources:
- ingress.yaml
- ../../$parent_path/manifests
patchesJson6902:
- target:
    group: pipelinesascode.tekton.dev
    version: v1alpha1
    kind: Repository
    name: gitops-repo
  path: patch-repo.yaml
- target:
    version: v1
    kind: Secret
    name: gitops-webhook-config
  path: patch-secret.yaml
- target:
    group: networking.k8s.io
    version: v1
    kind: Ingress
    name: pipelines-as-code
  path: patch-ingress.yaml
EOF

    else
	# kustomization.yaml
        cat <<EOF > ${TMP_DIR}/kustomization.yaml
resources:
- ../../$parent_path/manifests
patchesJson6902:
- target:
    group: pipelinesascode.tekton.dev
    version: v1alpha1
    kind: Repository
    name: gitops-repo
  path: patch-repo.yaml
- target:
    version: v1
    kind: Secret
    name: gitops-webhook-config
  path: patch-secret.yaml
EOF

    fi
    kubectl kustomize ${TMP_DIR} > ${TMP_DIR}/patched.yaml
    kubectl --kubeconfig=${KUBECONFIG} apply -f ${TMP_DIR}/patched.yaml
}

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

printf "Installing Pipelines as Code\n"

check_params
controller_install
mk_tmpdir

# Build kustomization and apply to cluster
kustomize

printf "Pipelines as Code installed\n"

