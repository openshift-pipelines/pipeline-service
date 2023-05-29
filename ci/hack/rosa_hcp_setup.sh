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
    ${0##*/} ./rosa_hcp_setup.sh [options]

Configure resources for ROSA HCP cluster on AWS

Mandatory arguments:
    -r, --region
        AWS region name.
    --prefix
        Prefix for the cluster name.
    -v, --version
        Version of the ROSA HCP cluster.
    
Optional arguments:
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.
Example:
    ${0##*/} ./rosa_hcp_setup.sh --prefix test0612 -r us-east-1 -v 4.12
" >&2
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        --prefix)
            shift
            export PREFIX_NAME="$1"
            ;;
        -r | --region)
            shift
            export AWS_REGION="$1"
            ;;
        -v | --version)
            shift
            export VERSION="$1"
            ;;
        -d | --debug)
            set -x
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
        esac
        shift
    done
}

init() {
    # Retrieve AWS Credential file from Bitwarden
    open_bitwarden_session
    get_aws_credentials
    get_rosa_token
}

prechecks() {
    if [[ -z "${PREFIX_NAME:-}" ]]; then
      printf "[ERROR] PREFIX_NAME is not set\n\n" >&2
      usage
      exit 1
    fi
    if [[ -z "${AWS_REGION:-}" ]]; then
      printf "[ERROR] AWS region is not set\n\n" >&2
      usage
      exit 1
    fi
    if [[ -z "${VERSION:-}" ]]; then
      printf "[ERROR] OCP version is not set\n\n" >&2
      usage
      exit 1
    fi
}

create_vpc() {
    # Create a directory for the Terraform files and navigate to it
    mkdir hypershift-tf
    cd hypershift-tf

    # Download the setup-vpc.tf file from GitHub
    curl --fail --silent --output setup-vpc.tf https://raw.githubusercontent.com/openshift-cs/OpenShift-Troubleshooting-Templates/master/rosa-hcp-terraform/setup-vpc.tf

    # Initialize Terraform
    terraform init

    # Plan the Terraform deployment and save the plan to a file
    terraform plan -out rosa.plan -var aws_region="$AWS_REGION" -var cluster_name="${PREFIX_NAME}"

    # Apply the Terraform plan
    terraform apply rosa.plan
}

create_account_roles() {
    local ROLE_PREFIX="${PREFIX_NAME}-role"
    # Login to the cluster
    rosa login --token="$ROSA_TOKEN"
    # Create the account-wide STS roles and policies
    role_output=$(rosa create account-roles --prefix "$ROLE_PREFIX" -f --mode auto -y --version "$VERSION")
    installer_role_arn=$(echo "$role_output" | awk -v prefix="$ROLE_PREFIX" '$0 ~ prefix"-Installer-Role" {gsub(/'\''/, "", $NF); print $NF}')
    # Create an OpenID Connect Configuration
    oidc_output=$(rosa create oidc-config --mode auto --managed --yes)
    oidc_config_id=$(echo "$oidc_output" | awk -F/ '{print $NF}')
    # Create Operator-roles
    rosa create operator-roles --prefix plnsvc-ci --oidc-config-id "$oidc_config_id" --installer-role-arn "$installer_role_arn" --hosted-cp --mode auto -y
}

main() {
    parse_args "$@"
    prechecks
    init
    create_vpc
    create_account_roles
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
