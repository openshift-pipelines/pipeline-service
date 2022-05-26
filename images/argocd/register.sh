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
    printf "
Usage:
    ${0##*/} [options]

Deploy Pipelines Service on the clusters as per the configuration in
WORKSPACE_DIR.

Optional arguments:
    -w, --workspace-dir WORKSPACE_DIR
        Location of the folder holding the clusters configuration.
        Default: current directory.
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/} -d /workspace
" >&2
}

parse_args() {
    WORKSPACE_DIR="$PWD"

    while [[ $# -gt 0 ]]; do
        case $1 in
        -w | --workspace-dir)
            shift
            WORKSPACE_DIR="$1"
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
    WORKSPACE_DIR=${WORKSPACE_DIR:-}
    if [[ -z "${WORKSPACE_DIR}" ]]; then
        printf "WORKSPACE_DIR not set\n\n"
        usage
        exit 1
    fi
}

process_clusters() {
    find "${WORKSPACE_DIR}/environment/compute" -name kustomization.yaml \
        -exec dirname {} \; \
    | while read -r cluster_dir ; do
        process_cluster
    done
}

process_cluster() {
    cluster_name="$(basename "$cluster_dir")"
    printf "Processing cluster %s:\n\t" "$cluster_name"
    KUBECONFIG="${WORKSPACE_DIR}/credentials/kubeconfig/compute/${cluster_name}.yaml"
    if [ ! -e "$KUBECONFIG" ]; then
        printf "[ERROR] Kubeconfig not found: %s\n" "$KUBECONFIG" >&2
        return
    fi
    KUBECONFIG="$KUBECONFIG" kubectl apply -k "$cluster_dir"
}

main() {
    parse_args "$@"
    prechecks
    process_clusters
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
