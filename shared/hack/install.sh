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
    echo "
Usage:
    ${0##*/} [options] --bin BIN_LIST

Install all the dependencies required to develop on the project.

Mandatory arguments:
    --bin \$BIN_LIST
        List of binaries to install

Optional arguments:
    --bin-dir \$BIN_DIR
        Path in which to install the binaries. It must be referenced by \$PATH.
        Default: '$BIN_DIR'.
    --dependencies \$DEPENDENCIES_PATH
        Path to the env file declaring the dependencies and their version.
        Default: '$DEPENDENCIES'.
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/} --bin-dir ~/bin --bin jq,yq
" >&2
}

init() {
    SCRIPT_DIR=$(
        cd "$(dirname "$0")" >/dev/null
        pwd
    )

    BIN_DIR="/usr/local/bin"
    TMPDIR=$(mktemp -d)
    TMPBIN="$TMPDIR/bin"
    mkdir -p "$TMPBIN"
    PATH="$TMPBIN:$PATH"

    DEPENDENCIES="${DEPENDENCIES:-$SCRIPT_DIR/../config/dependencies.sh}"
}

parse_args() {
    while [ $# -gt 0 ]; do
        case $1 in
        --bin)
            shift
            mapfile -t BIN_LIST < <(echo "$1" | tr ',' '\n')
            ;;
        --bin-dir)
            shift
            BIN_DIR="$1"
            ;;
        --dependencies)
            shift
            DEPENDENCIES="$1"
            ;;
        -d | --debug)
            DEBUG="--debug"
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

    DEBUG=${DEBUG:-}
    if [ -n "$DEBUG" ]; then
        set -x
    fi
}

check_vars() {
    if [ -z "${BIN_LIST[*]}" ]; then
        echo "[ERROR] Missing argument: --bin" >&2
        usage
        exit 1
    fi
    if [ ! -d "$BIN_DIR" ]; then
        echo "[ERROR] Could not find '$BIN_DIR'" >&2
        exit 1
    fi
    if [ ! -e "$DEPENDENCIES" ]; then
        echo "[ERROR] Could not find '$DEPENDENCIES'" >&2
        exit 1
    fi
}

install_dependencies() {
    # shellcheck source=shared/config/dependencies.sh
    source "$DEPENDENCIES"

    CURL_OPTS=("--fail" "--location" "--silent" "--show-error")

    for BIN in "${BIN_LIST[@]}"; do
        echo "[Installing $BIN]"
        "install_${BIN}"
        echo
    done
}

install_argocd() {
    curl "${CURL_OPTS[@]}" -o "$TMPBIN/argocd" "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
    move_bin
    argocd version --client --short
}

install_aws() {
    curl "${CURL_OPTS[@]}" -o "$TMPDIR/awscliv2.zip" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    unzip -q "$TMPDIR/awscliv2.zip" -d "$TMPDIR"
    "$TMPDIR/aws/install"
    aws --version
}

install_bitwarden() {
    curl "${CURL_OPTS[@]}" -o "$TMPDIR/bw.zip" "https://github.com/bitwarden/clients/releases/download/cli-${BITWARDEN_VERSION}/bw-linux-${BITWARDEN_VERSION:1}.zip"
    unzip -q "$TMPDIR/bw.zip" -d "$TMPBIN/"
    move_bin
    bw --version
}

install_checkov() {
    pip3 install --no-cache-dir checkov=="${CHECKOV_VERSION}"
    checkov --version
}

install_go() {
    curl "${CURL_OPTS[@]}" -o "$TMPDIR/go.tgz" "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
    tar -C /usr/local -xzf "$TMPDIR/go.tgz"
    ln -s /usr/local/go/bin/go /usr/bin/go
    go version
}

install_hadolint() {
    curl "${CURL_OPTS[@]}" -o "$TMPBIN/hadolint" "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-x86_64"
    move_bin
    hadolint --version
}

install_jq() {
    curl "${CURL_OPTS[@]}" -o "$TMPBIN/jq" "https://github.com/stedolan/jq/releases/download/jq-${JQ_VERSION}/jq-linux64"
    move_bin
    jq --version
}

install_kind() {
    curl "${CURL_OPTS[@]}" -o "$TMPBIN/kind" "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64"
    move_bin
    kind --version
}

install_kubectl() {
    curl "${CURL_OPTS[@]}" -o "$TMPBIN/kubectl" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    move_bin
    kubectl version --client
}

install_oc() {
    curl "${CURL_OPTS[@]}" -o "$TMPDIR/ocp-client.tgz" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OC_VERSION}/openshift-client-linux.tar.gz"
    tar -C "$TMPBIN" -xzf "$TMPDIR/ocp-client.tgz" oc
    move_bin
    oc version --client
}

install_rosa() {
    curl "${CURL_OPTS[@]}" -o "$TMPDIR/rosa.tgz" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/rosa/${ROSA_VERSION}/rosa-linux.tar.gz"
    tar -C "$TMPDIR" -xzf "$TMPDIR/rosa.tgz" --no-same-owner rosa
    mv "$TMPDIR/rosa" "$TMPBIN"
    move_bin
    rosa version
}

install_shellcheck() {
    curl "${CURL_OPTS[@]}" -o "$TMPDIR/shellcheck.tar.xz" "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.xz"
    tar -C "$TMPDIR" -xJf "$TMPDIR/shellcheck.tar.xz" "shellcheck-${SHELLCHECK_VERSION}/shellcheck"
    mv "$TMPDIR/shellcheck-${SHELLCHECK_VERSION}/shellcheck" "$TMPBIN"
    move_bin
    shellcheck --version
}

install_terraform() {
    curl "${CURL_OPTS[@]}" -o "$TMPDIR/terraform.zip" "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
    unzip -q "$TMPDIR/terraform.zip" -d "$TMPBIN/"
    move_bin
    terraform version
}

install_tkn() {
    curl "${CURL_OPTS[@]}" -o "$TMPDIR/tkn.tgz" "https://github.com/tektoncd/cli/releases/download/${TEKTONCD_CLI_VERSION}/tkn_${TEKTONCD_CLI_VERSION:1}_Linux_x86_64.tar.gz"
    tar -C "$TMPBIN" --no-same-owner -xzf "$TMPDIR/tkn.tgz" tkn
    move_bin
    tkn version
}

install_yamllint() {
    pip3 install --no-cache-dir yamllint=="${YAMLLINT_VERSION}"
    yamllint --version
}

install_yq() {
    curl "${CURL_OPTS[@]}" -o "$TMPBIN/yq" "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
    move_bin
    yq --version
}

move_bin() {
    # Make sure binaries are executable and move them to the target dir
    chmod +x "$TMPBIN"/*
    mv "$TMPBIN"/* "$BIN_DIR"
}

clean_up() {
    rm -rf "$TMPDIR"
}

main() {
    init
    parse_args "$@"
    check_vars
    install_dependencies
    clean_up
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
