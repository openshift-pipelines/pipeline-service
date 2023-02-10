#!/usr/bin/env bash

# Quit if exit status of any cmd is a non-zero value
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

PROJECT_DIR="$(
  cd "$SCRIPT_DIR/../.." >/dev/null || exit 1
  pwd
)"

# shellcheck source=ci/images/ci-runner/hack/bin/utils.sh
source "$PROJECT_DIR/ci/images/ci-runner/hack/bin/utils.sh"

usage() {
    echo "
Usage: 
    ${0##*/} ./hypershift_setup.sh [options]

Install HyperShift operator on ROSA cluster

Mandatory arguments:
    --kubeconfig
        path to HyperShift Compute KUBECONFIG.
    -r, --region
        AWS s3 region name.
    -n, --name
        AWS S3 bucket name.
    
Optional arguments:
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.
Example:
    ${0##*/} ./hypershift_setup.sh --region us-west-2
" >&2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    --kubeconfig)
      shift
      export KUBECONFIG="$1"
      ;;
    -r | --region)
      shift
      export BUCKET_REGION="$1"
      ;;
    -n | --name)
      shift
      export BUCKET_NAME="$1"
      ;;
    -d | --debug)
      set -x
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
    esac
      shift
  done
}

prechecks() {
    if [[ -z "$KUBECONFIG" ]]; then
      printf "HyperShift Compute KUBECONFIG is not set\n\n"
      usage
      exit 1
    fi
    if [[ -z "$BUCKET_REGION" ]]; then
      printf "AWS S3 region is not set\n\n"
      usage
      exit 1
    fi
    if [[ -z "$BUCKET_NAME" ]]; then
      printf "AWS S3 bucket name is not set\n\n"
      usage
      exit 1
    fi
}

create_s3_bucket() {
  # Check if the s3 bucket is there
  BUCKET_EXISTS=$(aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>&1 || true)
  if [ -z "$BUCKET_EXISTS" ]; then
    echo "Bucket $BUCKET_NAME exists"
  else
    echo "Bucket $BUCKET_NAME does not exist, start to create it"
    aws s3api create-bucket --acl public-read \
      --create-bucket-configuration LocationConstraint="$BUCKET_REGION" \
      --region "$BUCKET_REGION" \
      --bucket "$BUCKET_NAME"
  fi
}

init() {
  # Retrieve AWS Credential file from Bitwarden
  open_bitwarden_session
  get_aws_credentials
}

install_hypershift() {
  echo "HyperShift setup on ROSA cluster"
  # Install HyperShift operator
  hypershift install --oidc-storage-provider-s3-credentials "$AWS_CREDENTIALS" \
    --oidc-storage-provider-s3-bucket-name "$BUCKET_NAME" \
    --oidc-storage-provider-s3-region="$BUCKET_REGION"

  # Loop to check if the deployment is Available and Ready
  local ns="hypershift"
  if kubectl wait --for=condition=Available=true "deployment/operator" -n "$ns" --timeout=120s >/dev/null; then
    printf ", Ready\n"
  else
    kubectl -n "$ns" describe "deployment/operator"
    kubectl -n "$ns" logs "deployment/operator"
    kubectl -n "$ns" get events | grep Warning
    exit 1
  fi
}

main() {
  init
  parse_args "$@"
  prechecks
  create_s3_bucket
  install_hypershift
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
