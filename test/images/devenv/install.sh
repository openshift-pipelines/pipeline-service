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
    ${0##*/} [options]

Install all the dependencies required to develop on the project.

Optional arguments:
    --dependencies
        Path to the YAML file registering the dependencies and their version.
        Default: '$PROJECT_DIR/config/dependencies.yaml'.
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/}
" >&2
}

init() {
    SCRIPT_DIR=$(
        cd "$(dirname "$0")" >/dev/null
        pwd
    )
    PROJECT_DIR=$(
        cd "$SCRIPT_DIR/../../.." >/dev/null
        pwd
    )

    TMPDIR=$(mktemp -d)
    TMPBIN="$TMPDIR/bin"
    mkdir -p "$TMPBIN"
    PATH="$TMPBIN:$PATH"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
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

get_dependencies() {
    DEPENDENCIES="${DEPENDENCIES:-$PROJECT_DIR/config/DEPENDENCIES.yaml}"
    if [ ! -e "$DEPENDENCIES" ]; then
        echo "[ERROR] Could not find 'DEPENDENCIES.yaml'" >&2
        exit 1
    fi
}

install_dependencies() {
    CURL_OPTS=("--fail" "--location" "--silent" "--show-error")
    set -x

    # Install yq
    version="$(grep -E "^ *yq: " "$DEPENDENCIES" | sed 's/.*: //')"
    curl "${CURL_OPTS[@]}" -o "$TMPBIN/yq" "https://github.com/mikefarah/yq/releases/download/$version/yq_linux_amd64"
    chmod +x "$TMPBIN/yq"

    # Install argocd
    version="$(yq ".argocd" "$DEPENDENCIES")"
    curl "${CURL_OPTS[@]}" -o "$TMPBIN/argocd" "https://github.com/argoproj/argo-cd/releases/download/$version/argocd-linux-amd64"

    # Install hadolint
    version="$(yq ".hadolint" "$DEPENDENCIES")"
    curl "${CURL_OPTS[@]}" -o "$TMPBIN/hadolint" "https://github.com/hadolint/hadolint/releases/download/$version/hadolint-Linux-x86_64"

    # Install jq
    version="$(yq ".jq" "$DEPENDENCIES")"
    curl "${CURL_OPTS[@]}" -o "$TMPBIN/jq" "https://github.com/stedolan/jq/releases/download/jq-$version/jq-linux64"

    # Install kind
    version="$(yq ".kind" "$DEPENDENCIES")"
    curl "${CURL_OPTS[@]}" -o "$TMPBIN/kind" "https://github.com/kubernetes-sigs/kind/releases/download/$version/kind-linux-amd64"

    # Install kubectl kcp-plugin
    version="$(yq ".kcp" "$DEPENDENCIES")"
    version_short="$(echo "$version" | cut -c 2-)"
    curl "${CURL_OPTS[@]}" -o "$TMPDIR/kubectl-kcp.tar.gz" "https://github.com/kcp-dev/kcp/releases/download/$version/kubectl-kcp-plugin_${version_short}_linux_amd64.tar.gz"
    tar -C "$TMPDIR" -xz -f "$TMPDIR/kubectl-kcp.tar.gz" bin/kubectl-kcp

    # Install oc & kubectl
    version="$(yq ".oc-kubectl" "$DEPENDENCIES")"
    curl "${CURL_OPTS[@]}" -o "$TMPDIR/ocp-client.tar.gz" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$version/openshift-client-linux.tar.gz"
    tar -C "$TMPBIN" -xz -f "$TMPDIR/ocp-client.tar.gz" kubectl oc

    # Install shellcheck
    version="$(yq ".shellcheck" "$DEPENDENCIES")"
    curl "${CURL_OPTS[@]}" -o "$TMPDIR/shellcheck.tar.xz" "https://github.com/koalaman/shellcheck/releases/download/$version/shellcheck-$version.linux.x86_64.tar.xz"
    tar -C "$TMPDIR" -xJf "$TMPDIR/shellcheck.tar.xz" "shellcheck-$version/shellcheck"
    mv "$TMPDIR/shellcheck-$version/shellcheck" "$TMPBIN"

    # Install tkn
    version="$(yq ".tektoncd-cli" "$DEPENDENCIES")"
    version_short="$(echo "$version" | cut -c 2-)"
    if command -v rpm >/dev/null; then
        rpm -Uvh "https://github.com/tektoncd/cli/releases/download/$version/tektoncd-cli-${version_short}_Linux-64bit.rpm"
    elif command -v dpkg >/dev/null; then
        curl "${CURL_OPTS[@]}" -o "$TMPDIR/tektoncd-cli.deb" "https://github.com/tektoncd/cli/releases/download/$version/tektoncd-cli-${version_short}_Linux-64bit.deb"
        dpkg -i "$TMPDIR/tektoncd-cli.deb"
    else
        echo "[ERROR] Cannot install tekton: Unsupported OS" >&2
        exit 1
    fi
    if [ -z "$DEBUG" ]; then
        set +x
    fi

    # Make binaries executable and move them to a standard dir
    chmod +x "$TMPBIN"/*
    mv "$TMPBIN"/* /usr/local/bin/
}

check_install() {
    # Make sure everything is installed properly
    argocd version --client --short
    jq --version
    kind --version
    kubectl version --client
    kubectl-kcp --version
    oc version --client
    shellcheck --version
    tkn version
    yq --version
}

clean_up() {
    rm -rf "$TMPDIR"
}

main() {
    init
    parse_args "$@"
    get_dependencies
    install_dependencies
    clean_up
    check_install
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
