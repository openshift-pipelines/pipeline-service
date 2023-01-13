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
# shellcheck source=developer/images/dependencies-update/content/bin/task.sh
source "$SCRIPT_DIR/../task.sh"

run_task() {
    DEPENDENCIES="$WORKSPACE_DIR/shared/config/dependencies.sh"
    echo "Update binaries" >"$COMMIT_MSG"
    mapfile -t BINARIES < <(
        grep --extended-regexp "[A-Z]*_VERSION=" "$DEPENDENCIES" \
            | sed "s:export *\(.*\)_VERSION=.*:\1:" \
            | tr "[:upper:]" "[:lower:]" \
            | sort
    )
    for BINARY in "${BINARIES[@]}"; do
        update_binary
    done
    git diff shared/config/dependencies.sh \
        | grep "^+export" \
        | sed -e "s:^+export:-:" -e "s:_VERSION=: to :" \
        | tr -d \" \
        | tr "[:upper:]" "[:lower:]" >>"$COMMIT_MSG"
}

update_binary() {
    echo "$BINARY"
    "get_${BINARY}_version"
    BINARY=$(echo "$BINARY" | tr "[:lower:]" "[:upper:]")
    sed -i -e "s:\( ${BINARY}_VERSION\)=.*:\1=\"$VERSION\":" "$DEPENDENCIES"
}

get_argocd_version() {
    get_github_release "https://github.com/argoproj/argo-cd/releases/latest"
}

get_bitwarden_version() {
    get_github_release "https://github.com/bitwarden/clients/releases/latest"
    VERSION=$(echo "$VERSION" | sed "s:^cli-::")
}

get_checkov_version() {
    get_github_release "https://github.com/bridgecrewio/checkov/releases/latest"
}

get_go_version() {
    URL="https://go.dev/VERSION?m=text"
    VERSION=$(
        curl --location --silent "$URL" \
            | sed "s:^go::"
    )
}

get_grpc_cli_version() {
    URL="https://github.com/grpc/grpc.git"
    VERSION=$(
        git ls-remote --tags "$URL" \
            | grep -vE -- "-alpha|-beta|-pre|-rc|\^\{\}" \
            | sed "s:^.*refs/tags/::" \
            | sort -V \
            | tail -1
    )
}

get_hadolint_version() {
    get_github_release "https://github.com/hadolint/hadolint/releases/latest"
}

get_jq_version() {
    get_github_release "https://github.com/stedolan/jq/releases/latest"
    VERSION=$(echo "$VERSION" | sed "s:^jq-::")
}

get_kind_version() {
    get_github_release "https://github.com/kubernetes-sigs/kind/releases/latest"
}

get_kubectl_version() {
    URL="https://github.com/kubernetes/kubectl.git"
    VERSION=$(
        git ls-remote --tags "$URL" \
            | grep "tags/kubernetes-" \
            | grep -vE -- "-alpha|-beta|-pre|-rc|\^\{\}" \
            | sed "s:^.*refs/tags/kubernetes-::" \
            | sort -V \
            | tail -1
    )
    VERSION="v$VERSION"
}

get_oc_version() {
    URL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/"
    VERSION=$(
        curl --location --silent "$URL" \
        | grep -E ">openshift-client-linux-[0-9]" \
        | sed "s:.*\([0-9]\+\.[0-9]\+\.[0-9]\+\).*:\1:"
    )
}

get_shellcheck_version() {
    get_github_release "https://github.com/koalaman/shellcheck/releases/latest"
}

get_tektoncd_cli_version() {
    get_github_release "https://github.com/tektoncd/cli/releases/latest"
}

get_yamllint_version() {
    URL="https://github.com/adrienverge/yamllint.git"
    VERSION=$(
        git ls-remote --tags "$URL" \
            | grep -vE -- "-alpha|-beta|-pre|-rc|\^\{\}" \
            | sed "s:^.*refs/tags/::" \
            | sort -V \
            | tail -1
    )
    VERSION=$(echo "$VERSION" | sed "s:^v::")
}

get_yq_version() {
    get_github_release "https://github.com/mikefarah/yq/releases/latest"
}

get_github_release() {
    URL="$1"
    VERSION=$(
        curl --location --output /dev/null --silent --write-out "%{url_effective}" "$URL" \
            | sed "s:.*/::"
    )
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    run_task "$@"
fi
