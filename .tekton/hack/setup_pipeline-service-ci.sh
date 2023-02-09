#!/usr/bin/env bash

# Copyright 2023 The Pipeline Service Authors.
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

usage() {
    echo "
Usage:
    ${0##*/} [options]

Setup the pipeline-service-ci namespace on the cluster running the CI.
The user will be walked through all the steps to setup the connection to GitHub.

Optional arguments:
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/} --debug
" >&2
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        -d | --debug)
            set -x
            DEBUG="--debug"
            export DEBUG
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

init() {
    TMPDIR=$(mktemp -d)
}

apply_manifests() {
    echo "[Apply default config]"
    kubectl apply -k "$SCRIPT_DIR/../manifests"
}

generate_ssh_key() {
    ssh-keygen \
        -f "$TMPDIR/secret/ssh-privatekey" \
        -q \
        -t ed25519 \
        -C "pipeline-service-ci" \
        -N ""
}

setup_ssh_secret_directory() {
    mv "$TMPDIR/secret/ssh-privatekey.pub" "$TMPDIR/secret/ssh-publickey"
    cat <<EOF >"$TMPDIR/secret/known_hosts"
github.com,140.82.112.3 ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==
EOF
}

create_ssh_secret() {
    kubectl create secret generic ssh-key --namespace pipeline-service-ci \
        --from-file="$TMPDIR/secret" \
        --type kubernetes.io/ssh-auth
    kubectl annotate secret ssh-key --namespace pipeline-service-ci \
        "tekton.dev/git-0=github.com" # Flag the secret to be used to connect to GitHub
}

register_ssh_key() {
    echo "Register the public key and enable 'Allow write access':"
    echo "    URL: https://github.com/openshift-pipelines/pipeline-service/settings/keys"
    echo "    Public key: $(cat "$TMPDIR/secret/ssh-publickey")"
    read -rs -p "Press Enter to continue... "
}

generate_ssh_secret() {
    # c.f. https://github.com/tektoncd/pipeline/blob/main/docs/auth.md
    echo "[Generate GitHub SSH secret]"
    mkdir -p "$TMPDIR/secret"
    generate_ssh_key
    setup_ssh_secret_directory
    create_ssh_secret
    register_ssh_key
    rm -rf "$TMPDIR/secret"
    echo
}

generate_token() {
    echo "Generate a token by visiting https://github.com/settings/tokens?type=beta"
    read -rs -p "Token: " token
    echo -n "$token" >"$TMPDIR/secret/token"
}

create_token_secret() {
    kubectl create secret generic github --namespace pipeline-service-ci --from-file="$TMPDIR/secret"
    rm -rf "$TMPDIR/secret"
}

generate_token_secret() {
    echo "[Generate GitHub token secret]"
    mkdir -p "$TMPDIR/secret"
    generate_token
    create_token_secret
    rm -rf "$TMPDIR/secret"
    echo
}

main() {
    if [ -n "${DEBUG:-}" ]; then
        set -x
    fi
    parse_args "$@"
    init
    apply_manifests
    generate_ssh_secret
    generate_token_secret
    rm -rf "$TMPDIR"
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
