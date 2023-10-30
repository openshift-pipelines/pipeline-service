#!/usr/bin/env bash

# Quit if exit status of any cmd is a non-zero value
set -o errexit
set -o nounset
set -o pipefail

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
    --name
        Name for the cluster name.
    
Optional arguments:
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.
Example:
    ${0##*/} ./rosa_hcp_setup.sh --name <cluster-name> -r us-east-1
" >&2
}

init() {
    SCRIPT_DIR="$(
        cd "$(dirname "$0")" >/dev/null
        pwd
    )"

    PROJECT_DIR="$(
        cd "$SCRIPT_DIR/../.." >/dev/null || exit 1
        pwd
    )"

    TMPDIR=$(dirname "$(mktemp -u)")
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        --name)
            shift
            export CLUSTER_NAME="$1"
            ;;
        -r | --region)
            shift
            export AWS_REGION="$1"
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

prechecks() {
    # if rosa is not login, exit
    if ! rosa whoami; then
        printf "[ERROR] rosa is not login\n\n" >&2
        usage
        exit 1
    fi

    if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
        printf "[ERROR] AWS_ACCESS_KEY_ID variable is not set\n\n" >&2
        usage
        exit 1
    fi

    if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        printf "[ERROR] AWS_SECRET_ACCESS_KEY variable is not set\n\n" >&2
        usage
        exit 1
    fi

    if [[ -z "${CLUSTER_NAME:-}" ]]; then
        printf "[ERROR] cluster name is not set\n\n" >&2
        usage
        exit 1
    fi
    if [[ -z "${AWS_REGION:-}" ]]; then
        printf "[ERROR] AWS region is not set\n\n" >&2
        usage
        exit 1
    fi
}

create_vpc() {
    cd "${TMPDIR}" || exit 1
    git clone https://github.com/openshift-cs/terraform-vpc-example.git
    cd terraform-vpc-example

    # Initialize Terraform
    terraform init

    # Plan the Terraform deployment and save the plan to a file
    terraform plan -out rosa.tfplan -var region="$AWS_REGION" -var cluster_name="${CLUSTER_NAME}"

    # Apply the Terraform planc
    terraform apply rosa.tfplan
    # save file `terraform.tfstate` to the current directory for VPC cleanup
    cp "${TMPDIR}/terraform-vpc-example/terraform.tfstate" "${SCRIPT_DIR}"/terraform.tfstate_"${CLUSTER_NAME}"
}

create_resources() {
    local ROLE_PREFIX="${CLUSTER_NAME}-role"
    # Create the account-wide STS roles and policies
    rosa create account-roles --prefix "$ROLE_PREFIX" --hosted-cp -f --mode auto -y
    installer_role_arn=$(rosa list account-roles | grep "$ROLE_PREFIX"-HCP-ROSA-Installer-Role | awk '{print $3}')

    # Create an OpenID Connect Configuration
    rosa create oidc-config -y --mode auto --output json --managed \
        >"${TMPDIR}/oidc-config"
    oidc_config_id=$(jq -r '.id' "${TMPDIR}/oidc-config")
    # Create Operator-roles
    rosa create operator-roles --prefix "${CLUSTER_NAME}" --oidc-config-id "${oidc_config_id}" --installer-role-arn "${installer_role_arn}" --hosted-cp --mode auto -y
}

clean_up() {
    rm -rf "${TMPDIR}"
}

main() {
    init
    parse_args "$@"
    prechecks
    create_vpc
    create_resources
    clean_up
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
