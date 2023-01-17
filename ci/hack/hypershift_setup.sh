#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -o errexit
set -o nounset
set -o pipefail

usage() {
    echo "
Usage: 
    ${0##*/} ./hypershift_setup.sh [options]

Install HyperShift operator on ROSA cluster

Mandatory arguments:
    --kubeconfig
        path to HyperShift Compute KUBECONFIG.
    --secret
        path to HyperShift pull secret.
    --url
        HyperShift base domain url.
    --id
        AWS access key id.
    --key
        AWS secret access key.
    -r, --region
        AWS region name.
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
    --secret)
      shift
      export HYPERSHIFT_PULL_SECRET="$1"
      ;;
    --url)
      shift
      export HYPERSHIFT_BASE_DOMAIN="$1"
      ;;
    --id)
      shift
      export AWS_ACCESS_KEY_ID="$1"
      ;;
    --key)
      shift
      export AWS_SECRET_ACCESS_KEY="$1"
      ;;
    -r | --region)
      shift
      export AWS_REGION="$1"
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
    if [[ -z "$HYPERSHIFT_PULL_SECRET" ]]; then
      printf "HyperShift pull secret is not set\n\n"
      usage
      exit 1
    fi
    if [[ -z "$HYPERSHIFT_BASE_DOMAIN" ]]; then
      printf "HyperShift base domain url is not set\n\n"
      usage
      exit 1
    fi
    if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
      printf "AWS access key id is not set\n\n"
      usage
      exit 1
    fi
    if [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
      printf "AWS secret access key is not set\n\n"
      usage
      exit 1
    fi
    if [[ -z "$AWS_REGION" ]]; then
      printf "AWS region is not set\n\n"
      usage
      exit 1
    fi
    if [[ -z "$BUCKET_NAME" ]]; then
      printf "AWS S3 bucket name is not set\n\n"
      usage
      exit 1
    fi
}

init() {
  SCRIPT_DIR=$(
    cd "$(dirname "$0")" >/dev/null
    pwd
  )
}

install_hypershift() {
  echo "HyperShift setup on ROSA cluster"
  # Enable HyperShift and make ROSA cluster a managed cluster, visit documentation https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.6/html-single/multicluster_engine/index#hosted-control-planes-configure 
  kubectl apply -f "$SCRIPT_DIR/ci/manifests/hypershift/multi_cluster_engine.yaml"
  kubectl apply -f "$SCRIPT_DIR/ci/manifests/hypershift/manage_cluster.yaml"

  # Create an S3 bucket for HyperShift Operator with public-read
  aws s3api create-bucket --acl public-read --bucket "$BUCKET_NAME" \
    --create-bucket-configuration LocationConstraint="$AWS_REGION" \
    --region "$AWS_REGION"

  # Create an OIDC S3 credentials secret
  oc create secret generic hypershift-operator-oidc-provider-s3-credentials \
    --from-file=credentials="$HOME/.aws/credentials" \
    --from-literal=bucket="$BUCKET_NAME" \
    --from-literal=region="$AWS_REGION" -n local-cluster

  # Install HyperShift operator on the managed cluster
  kubectl apply -f "$SCRIPT_DIR/ci/manifests/hypershift/hypershift_operator_install.yaml"
  # Wait for HyperShift operator to be installed
  while [ "$(kubectl -n local-cluster get ManagedClusterAddOn | grep -cE "hypershift-addon")" != "1" ]; do
      echo -n "."
      sleep 2
  done
  echo "HyperShift operator successfully installed on the managed cluster"

  # Create AWS credential secret
  kubectl create ns ci-clusters

  oc create secret generic my-aws-cred -n ci-clusters \
    --from-literal=baseDomain="$HYPERSHIFT_BASE_DOMAIN" \
    --from-literal=aws_access_key_id="$AWS_ACCESS_KEY_ID" \
    --from-literal=aws_secret_access_key="$AWS_SECRET_ACCESS_KEY" \
    --from-literal=pullSecret="$HYPERSHIFT_PULL_SECRET" \
    --from-file=ssh-publickey="$HOME/.ssh/id_rsa.pub" \
    --from-file=ssh-privatekey="$HOME/.ssh/id_rsa"
}

main() {
  init
  parse_args "$@"
  prechecks
  install_hypershift
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi