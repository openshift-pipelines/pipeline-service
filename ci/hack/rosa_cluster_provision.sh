#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -o errexit
set -o nounset
set -o pipefail

usage() {
    echo "
Usage: 
    ${0##*/} ./rosa_cluster_provision.sh [options]

Provision a ROSA cluster

Mandatory arguments:
    -t, --token
        API token to authenticate against the Red Hat OpenShift Service on AWS account.
    --id
        AWS access key id.
    --key
        AWS secret access key.
    -r, --region
        AWS region name.
    -n, --name
        name of the cluster.
    
Optional arguments:
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.
Example:
    ${0##*/} ./rosa_cluster_provision.sh --token <ROSA-API-TOKEN> --region us-west-2
" >&2

}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    -t | --token)
      shift
      export ROSA_TOKEN="$1"
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
      export CLUSTER_NAME="$1"
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
    if [[ -z "$ROSA_TOKEN" ]]; then
      printf "ROSA API authentication token is not set\n\n"
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
    if [[ -z "$CLUSTER_NAME" ]]; then
      printf "Cluster name is not set\n\n"
      usage
      exit 1
    fi
}

init() {
  tmpdir=$(mktemp -d)
  cd "$tmpdir"  
}

provision_rosa_cluster() {
  # This repo has the ROSA provision and destroy cluster scripts
  git clone --branch main git@github.com:stolostron/bootstrap-ks.git
  cd bootstrap-ks/rosa
  git checkout 1200f8b7
  ./install.sh
  ./provision.sh
}

main() {
  init
  parse_args "$@"
  prechecks
  provision_rosa_cluster
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi