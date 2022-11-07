#!/usr/bin/env bash

# Copyright 2022 The Pipeline Service Authors.
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

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

# shellcheck source=operator/images/access-setup/content/bin/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  printf "Usage:
    %s [options]

Generate access credentials for a new compute cluster so it can be managed by pipelines as code

Mandatory arguments:
    -k, --kubeconfig KUBECONFIG
        kubeconfig to the kcp instance to configure.
        The current context will be used.
        Default value: \$KUBECONFIG

Optional arguments:
    --kustomization KUSTOMIZATION
        path to the directory holding the kustomization.yaml to apply.
        Can be read from \$KUSTOMIZATION.
        Default: %s
    --git-remote-url GIT_URL
        Git repo to be referenced to apply various customizations.
        Can be read from \$GIT_URL.
        Default: %s
    --git-remote-ref GIT_REF
        Git repo's ref to be referenced to apply various customizations.
        Can be read from \$GIT_REF.
        Default: %s
    --tekton-results-database-user TEKTON_RESULTS_DATABASE_USER
        Username for tekton results database.
        Can be read from \$TEKTON_RESULTS_DATABASE_USER
        Default: %s
    --tekton-results-database-password TEKTON_RESULTS_DATABASE_PASSWORD
        Password for tekton results database.
        Can be read from \$TEKTON_RESULTS_DATABASE_PASSWORD
        Default: %s
    -w, --work-dir WORK_DIR
        Directory into which the credentials folder will be created.
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.
Example:
    %s -d -k /path/to/compute.kubeconfig
" "${0##*/}" "$KUSTOMIZATION" "$GIT_URL" "$GIT_REF" "$TEKTON_RESULTS_DATABASE_USER" "$TEKTON_RESULTS_DATABASE_PASSWORD" "${0##*/}" >&2
}

parse_args() {
  KUSTOMIZATION=${KUSTOMIZATION:-github.com/openshift-pipelines/pipeline-service/operator/gitops/compute/pipeline-service-manager?ref=main}
  GIT_URL=${GIT_URL:-"https://github.com/openshift-pipelines/pipeline-service.git"}
  GIT_REF=${GIT_REF:="main"}
  TEKTON_RESULTS_DATABASE_USER=${TEKTON_RESULTS_DATABASE_USER:-}
  TEKTON_RESULTS_DATABASE_PASSWORD=${TEKTON_RESULTS_DATABASE_PASSWORD:-}

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -k | --kubeconfig)
      shift
      KUBECONFIG="$1"
      ;;
    --kustomization)
      shift
      KUSTOMIZATION="$1"
      ;;
    --git-remote-url)
      shift
      GIT_URL="$1"
      ;;
    --git-remote-ref)
      shift
      GIT_REF="$1"
      ;;
    --tekton-results-database-user)
      shift
      TEKTON_RESULTS_DATABASE_USER="$1"
      ;;
    --tekton-results-database-password)
      shift
      TEKTON_RESULTS_DATABASE_PASSWORD="$1"
      ;;
    -w | --work-dir)
      shift
      WORK_DIR="$1"
      ;;
    -d | --debug)
      set -x
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      # End of arguments
      break
      ;;
    *)
      exit_error "Unknown argument: $1"
      ;;
    esac
    shift
  done
}

prechecks() {
  KUBECONFIG=${KUBECONFIG:-}
  if [[ -z "${KUBECONFIG}" ]]; then
    exit_error "Missing parameter --kubeconfig"
  fi
  if [[ ! -f "$KUBECONFIG" ]]; then
    echo "File not found: $KUBECONFIG" >&2
    exit 1
  fi
  export KUBECONFIG

  WORK_DIR=${WORK_DIR:-./work}
}

init() {
  WORK_DIR="${WORK_DIR:-$SCRIPT_DIR/work}"

  credentials_dir="$WORK_DIR/credentials/kubeconfig"
  manifests_dir="$WORK_DIR/credentials/manifests"
  mkdir -p "$credentials_dir"
  mkdir -p "$manifests_dir"
}

check_prerequisites() {
  # Check that argocd has been installed
  if [[ $(kubectl api-resources | grep -c "argoproj.io/") = "0" ]]; then
    echo "Argo CD must be deployed on the cluster first" >&2
    exit 1
  fi
}

generate_shared_manifests(){
  printf -- "- Generating shared manifests:\n"
  printf -- "  - tekton-chains manifest:\n"
  tekton_chains_manifest 2>&1 | indent 4
  printf -- "  - tekton-results manifest:\n"
  tekton_results_manifest 2>&1 | indent 4
}

tekton_chains_manifest(){
  manifest="$manifests_dir/compute/tekton-chains/signing-secrets.yaml"
  if [ ! -e "$manifest" ]; then
    manifests_tmp_dir="$(dirname "$manifest")/tmp"
    mkdir -p "$manifests_tmp_dir"
    cosign_passwd="$( head -c 12 /dev/urandom | base64 )"
    echo -n "$cosign_passwd" > "$manifests_tmp_dir/cosign.password"
    cosign_image="quay.io/redhat-appstudio/appstudio-utils:eb94f28fe2d7c182f15e659d0fdb66f87b0b3b6b"
    podman run \
      --rm \
      --env COSIGN_PASSWORD="$cosign_passwd" \
      --volume "$manifests_tmp_dir":/workspace:z \
      --workdir /workspace \
      --entrypoint /usr/bin/cosign \
      "$cosign_image" generate-key-pair
    {
      echo "---"
      kubectl create namespace tekton-chains --dry-run=client -o yaml
      echo "---"
      kubectl create secret generic -n tekton-chains signing-secrets --from-file="$manifests_tmp_dir" --dry-run=client -o yaml | \
        yq '. += {"immutable" :true}' | \
        yq "sort_keys(.)"
    } > "$manifest"
    rm -rf "$manifests_tmp_dir"
    if [ "$(yq ".data" < "$manifest" | grep -cE "^cosign.key:|^cosign.password:|^cosign.pub:")" != "3" ]; then
      printf "[ERROR] Invalid manifest: '%s'" "$manifest" >&2
      exit 1
    fi
  fi
  printf "OK\n"
}

tekton_results_manifest(){
  manifest="$manifests_dir/compute/tekton-results/tekton-results-secret.yaml"
  if [ ! -e "$manifest" ]; then
    manifests_dir="$(dirname "$manifest")"
    mkdir -p "$manifests_dir"
    if [[ -z $TEKTON_RESULTS_DATABASE_USER || -z $TEKTON_RESULTS_DATABASE_PASSWORD ]]; then
      printf "[ERROR] Tekton results database variable is not set, either set the variables using \n \
      the config.yaml under tekton_results_db \n \
      Or create '%s' \n" "$manifest" >&2
      exit 1
    fi

    {
      echo "---"
      kubectl create namespace tekton-results --dry-run=client -o yaml
      echo "---"
      kubectl create secret generic -n tekton-results tekton-results-database --from-literal=DATABASE_USER="$TEKTON_RESULTS_DATABASE_USER" --from-literal=DATABASE_PASSWORD="$TEKTON_RESULTS_DATABASE_PASSWORD" --dry-run=client -o yaml
    } > "$manifest"
    if [ "$(yq ".data" < "$manifest" | grep -cE "DATABASE_USER|DATABASE_PASSWORD")" != "2" ]; then
      printf "[ERROR] Invalid manifest: '%s'" "$manifest" >&2
      exit 1
    fi
  fi
  printf "OK\n"
}

generate_compute_credentials() {
  current_context=$(kubectl config current-context)
  compute_name="$(yq '.contexts[] | select(.name == "'"$current_context"'") | .context.cluster' < "$KUBECONFIG" | sed 's/:.*//')"
  printf "[Compute: %s]\n" "$compute_name"
  kubeconfig="$credentials_dir/compute/$compute_name.kubeconfig"

  printf -- "- Create ServiceAccount for Pipelines as Code:\n"
  kubectl apply -k "$KUSTOMIZATION" | indent 4

  printf -- "- Generate kubeconfig:\n"
  get_context "pipeline-service-manager" "pipelines-as-code" "pipeline-service-manager" "$kubeconfig"
  printf "KUBECONFIG=%s\n" "$kubeconfig" | indent 4

  printf "    - Generate kustomization.yaml: "
  manifests_dir="$WORK_DIR/environment/compute/$compute_name"
  mkdir -p "$manifests_dir"
  echo -n "---
resources:
  - git::$GIT_URL/operator/gitops/argocd?ref=$GIT_REF
" >"$manifests_dir/kustomization.yaml"
  printf "%s\n" "$manifests_dir/kustomization.yaml"
}

main() {
  parse_args "$@"
  prechecks
  init
  check_prerequisites
  generate_shared_manifests
  generate_compute_credentials
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
