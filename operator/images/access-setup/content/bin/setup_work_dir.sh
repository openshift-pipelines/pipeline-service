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

Setup working directory for Pipeline Service

Optional arguments:
    --kustomization KUSTOMIZATION
        path to the directory or manifest holding the configuration to deploy
        Pipeline Service via ArgoCD.
        Can be read from \$KUSTOMIZATION.
        Default: %s
    -w, --work-dir WORK_DIR
        Directory into which the credentials folder will be created.
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.
Example:
    %s -d 
" "${0##*/}" "$KUSTOMIZATION"  "${0##*/}" >&2
}

parse_args() {
  KUSTOMIZATION=${KUSTOMIZATION:-github.com/openshift-pipelines/pipeline-service/operator/gitops/argocd?ref=main}

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --kustomization)
      shift
      KUSTOMIZATION="$1"
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

# Checks if a binary is present on the local system
precheck_binary() {
  for binary in "$@"; do
    command -v "$binary" >/dev/null 2>&1 || {
      echo "[ERROR] This script requires '$binary' to be installed on your local machine." >&2
      exit 1
    }
  done
}

init() {
  WORK_DIR="${WORK_DIR:-./work}"
  manifests_dir="$WORK_DIR/credentials/manifests"
  mkdir -p "$manifests_dir"

  TEKTON_RESULTS_DATABASE_USER=${TEKTON_RESULTS_DATABASE_USER:="tekton"}
  TEKTON_RESULTS_DATABASE_PASSWORD=${TEKTON_RESULTS_DATABASE_PASSWORD:=$(openssl rand -base64 20)}

  detect_container_engine
}

detect_container_engine() {
    CONTAINER_ENGINE="${CONTAINER_ENGINE:-}"
    if [[ -n "${CONTAINER_ENGINE}" ]]; then
      return
    fi
    CONTAINER_ENGINE=podman
    if ! command -v podman >/dev/null; then
        CONTAINER_ENGINE=docker
    elif [[ "$OSTYPE" == "darwin"* && -z "$(podman ps)" ]]; then
        # Podman machine is not started
        CONTAINER_ENGINE=docker
    elif [[ "$OSTYPE" == "darwin"* && -z "$(podman system connection ls --format=json)" ]]; then
        CONTAINER_ENGINE=docker
    fi
    command -v "${CONTAINER_ENGINE}" >/dev/null
}

generate_shared_manifests(){
  printf -- "- Generating shared manifests:\n"
  printf -- "  - tekton-chains manifest:\n"
  tekton_chains_manifest 2>&1 | indent 4
  printf -- "  - tekton-results manifest:\n"
  tekton_results_manifest 2>&1 | indent 4
}

configure_argocd_apps(){
  printf -- "- Setting kustomize directory: "
  current_context=$(kubectl config current-context)
  compute_name="$(yq '.contexts[] | select(.name == "'"$current_context"'") | .context.cluster' < "$KUBECONFIG" | sed 's/:.*//')"
  manifests_dir="$WORK_DIR/environment/compute/$compute_name"
  mkdir -p "$manifests_dir"
  echo -n "---
resources:
  - $KUSTOMIZATION
" >"$manifests_dir/kustomization.yaml"
  printf "%s\n" "$manifests_dir"
}

tekton_chains_manifest(){
  chains_kustomize="$manifests_dir/compute/tekton-chains/kustomization.yaml"
  chains_namespace="$manifests_dir/compute/tekton-chains/namespace.yaml"
  chains_secret="$manifests_dir/compute/tekton-chains/signing-secrets.yaml"
  if [ ! -e "$chains_kustomize" ]; then
    chains_tmp_dir="$(dirname "$chains_kustomize")/tmp"
    mkdir -p "$chains_tmp_dir"
    cosign_passwd="$( head -c 12 /dev/urandom | base64 )"
    echo -n "$cosign_passwd" > "$chains_tmp_dir/cosign.password"
    cosign_image="quay.io/redhat-appstudio/appstudio-utils:eb94f28fe2d7c182f15e659d0fdb66f87b0b3b6b"
    $CONTAINER_ENGINE run \
      --rm \
      --env COSIGN_PASSWORD="$cosign_passwd" \
      --volume "$chains_tmp_dir":/workspace:z \
      --workdir /workspace \
      --entrypoint /usr/bin/cosign \
      "$cosign_image" generate-key-pair
    kubectl create namespace tekton-chains --dry-run=client -o yaml > "$chains_namespace"
    kubectl create secret generic -n tekton-chains signing-secrets --from-file="$chains_tmp_dir" --dry-run=client -o yaml | \
            yq '. += {"immutable" :true}' | \
            yq "sort_keys(.)" > "$chains_secret"
    yq e -n '.resources += ["namespace.yaml", "signing-secrets.yaml"]' > "$chains_kustomize"
    rm -rf "$chains_tmp_dir"
    if [ "$(yq ".data" < "$chains_secret" | grep -cE "^cosign.key:|^cosign.password:|^cosign.pub:")" != "3" ]; then
      printf "[ERROR] Invalid manifest: '%s'" "$chains_secret" >&2
      exit 1
    fi
  fi
  printf "OK\n"
}

tekton_results_manifest(){
  results_kustomize="$manifests_dir/compute/tekton-results/kustomization.yaml"
  results_namespace="$manifests_dir/compute/tekton-results/namespace.yaml"
  results_db_secret="$manifests_dir/compute/tekton-results/tekton-results-db-secret.yaml"
  results_s3_secret="$manifests_dir/compute/tekton-results/tekton-results-s3-secret.yaml"
  results_minio_user="$manifests_dir/compute/tekton-results/tekton-results-minio-user.yaml"
  results_minio_config="$manifests_dir/compute/tekton-results/tekton-results-minio-config.yaml"
  if [ ! -e "$results_kustomize" ]; then
    results_dir="$(dirname "$results_kustomize")"
    mkdir -p "$results_dir"
    if [[ -z $TEKTON_RESULTS_DATABASE_USER || -z $TEKTON_RESULTS_DATABASE_PASSWORD ]]; then
      printf "[ERROR] Tekton results database credentials are not set, either set the env variables using \n \
      the config.yaml under tekton_results_db \n \
      Or create '%s' \n" "$results_db_secret" >&2
      exit 1
    fi
    if [[ -z $TEKTON_RESULTS_S3_USER || -z $TEKTON_RESULTS_S3_PASSWORD ]]; then
      printf "[ERROR] Tekton results s3 credentials are not set, either set the variables using \n \
      the config.yaml under tekton_results_s3 \n \
      Or create '%s' \n" "$results_s3_secret" >&2
      exit 1
    fi

    kubectl create namespace tekton-results --dry-run=client -o yaml > "$results_namespace"
    yq -n '.resources += ["namespace.yaml"]' > "$results_kustomize"

    db_secret="$(kubectl get secret tekton-results-database -n tekton-results -o name --ignore-not-found)"
    if [ -z "$db_secret" ]; then
      echo 'Tekton Results database secrets not found, new secrets will be created'
      kubectl create secret generic -n tekton-results tekton-results-database \
      --from-literal=db.user="$TEKTON_RESULTS_DATABASE_USER" \
      --from-literal=db.password="$TEKTON_RESULTS_DATABASE_PASSWORD" \
      --from-literal=db.host="postgres-postgresql.tekton-results.svc.cluster.local" \
      --from-literal=db.name="tekton_results" \
      --dry-run=client -o yaml > "$results_db_secret"
      yq -i '.resources += ["tekton-results-db-secret.yaml"]' "$results_kustomize"
    fi

    s3_secret="$(kubectl get secret tekton-results-s3 -n tekton-results -o name --ignore-not-found)"
    if [ -z "$s3_secret" ]; then
      echo 'Tekton Results S3 secrets not found, new secrets will be created'
      kubectl create secret generic -n tekton-results tekton-results-s3 \
      --from-literal=aws_access_key_id="$TEKTON_RESULTS_S3_USER" \
      --from-literal=aws_secret_access_key="$TEKTON_RESULTS_S3_PASSWORD" \
      --from-literal=aws_region='not-applicable' \
      --from-literal=bucket=tekton-results \
      --from-literal=endpoint='http://minio.tekton-results.svc.cluster.local' \
      -n tekton-results --dry-run=client -o yaml > "$results_s3_secret"

      kubectl create secret generic -n tekton-results minio-user \
      --from-literal=CONSOLE_ACCESS_KEY="$TEKTON_RESULTS_S3_USER" \
      --from-literal=CONSOLE_SECRET_KEY="$TEKTON_RESULTS_S3_PASSWORD" \
      -n tekton-results --dry-run=client -o yaml > "$results_minio_user"

      cat <<EOF | kubectl apply -f - --dry-run=client -o yaml > "$results_minio_config"
apiVersion: v1
kind: Secret
metadata:
  name: minio-configuration
  namespace: tekton-results
type: Opaque
stringData:
  config.env: |-
    export MINIO_ROOT_USER="minio"
    export MINIO_ROOT_PASSWORD="$(openssl rand -base64 20)"
    export MINIO_STORAGE_CLASS_STANDARD="EC:1"
    export MINIO_BROWSER="on"
EOF
      yq -i '.resources += ["tekton-results-s3-secret.yaml", "tekton-results-minio-user.yaml", "tekton-results-minio-config.yaml"]' "$results_kustomize"
    fi
  fi
  printf "OK\n"
}

main() {
  parse_args "$@"
  precheck_binary "kubectl" "yq"
  init
  generate_shared_manifests
  configure_argocd_apps
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
