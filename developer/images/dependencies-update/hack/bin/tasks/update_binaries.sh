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
# shellcheck source=developer/images/dependencies-update/hack/bin/task.sh
source "$SCRIPT_DIR/../task.sh"

run_task() {
    DEPENDENCIES="$WORKSPACE_DIR/shared/config/dependencies.sh"
    echo "Update binaries" >"$COMMIT_MSG"
    mapfile -t BINARIES < <(
        grep --extended-regexp "^ *[^#]* *[A-Z]*_VERSION=" "$DEPENDENCIES" \
            | sed "s:export *\(.*\)_VERSION=.*:\1:" \
            | tr "[:upper:]" "[:lower:]" \
            | sort
    )
    for BINARY in "${BINARIES[@]}"; do
        update_binary
    done
    if [ $(git diff shared/config/dependencies.sh | wc -l) != "0" ]; then
        git diff shared/config/dependencies.sh \
            | grep "^+export" \
            | sed -e "s:^+export:-:" -e "s:_VERSION=: to :" \
            | tr -d \" \
            | tr "[:upper:]" "[:lower:]" >>"$COMMIT_MSG"
    fi
}

update_binary() {
    if grep --ignore-case --quiet " ${BINARY}_VERSION=.*# *Freeze" "$DEPENDENCIES"; then
        # Ignore frozen dependencies
        return
    fi
    echo -n "  - $BINARY: "
    unset VERSION
    "get_${BINARY}_version"
    echo "$VERSION"
    BINARY=$(echo "$BINARY" | tr "[:lower:]" "[:upper:]")
    sed -i -e "s:\( ${BINARY}_VERSION\)=.*:\1=\"$VERSION\":" "$DEPENDENCIES"
}

get_argocd_version() {
    get_github_release "https://github.com/argoproj/argo-cd"
}

get_bitwarden_version() {
    get_github_release "https://github.com/bitwarden/clients" "cli-"
    VERSION=$(echo "$VERSION" | sed "s:^cli-::")
}

get_checkov_version() {
    get_github_release "https://github.com/bridgecrewio/checkov"
}

get_go_version() {
    URL="https://go.dev/VERSION?m=text"
    VERSION=$(
        curl --location --silent "$URL" \
            | grep "^go" \
            | sed "s:^go::"
    )
}

get_hadolint_version() {
    get_github_release "https://github.com/hadolint/hadolint"
}

get_jq_version() {
    get_github_release "https://github.com/stedolan/jq" "jq-"
}

get_kind_version() {
    get_github_release "https://github.com/kubernetes-sigs/kind"
}

get_kubectl_version() {
    get_github_release "https://github.com/kubernetes/kubectl.git" "kubernetes-"
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

get_rosa_version() {
    get_github_release "https://github.com/openshift/rosa"
    VERSION=$(echo "$VERSION" | sed "s:^v::")
}

get_shellcheck_version() {
    get_github_release "https://github.com/koalaman/shellcheck"
}

get_tektoncd_cli_version() {
    get_github_release "https://github.com/tektoncd/cli"
}

get_terraform_version() {
    URL="https://api.github.com/repos/hashicorp/terraform/releases/latest"
    VERSION=$(
        curl --location --silent "$URL" \
            | grep '"tag_name":' \
            | sed -E 's/.*"([^"]+)".*/\1/' \
            | sed "s:^v::"
    )
}

get_yamllint_version() {
    get_github_release "https://github.com/adrienverge/yamllint.git" "v"
}

get_yq_version() {
    get_github_release "https://github.com/mikefarah/yq"
}

get_github_release() {
    URL="$1"
    PREFIX="${2:-}"
    VERSION=$(
        git ls-remote --tags "$URL" \
            | grep -E "$PREFIX" \
            | grep -E "[0-9]+\.[0-9]+" \
            | grep -vE "[0-9]-*alpha|[0-9]-*beta|[0-9]-*pre|[0-9]-*rc|\^\{\}" \
            | sed "s:^.*refs/tags/$PREFIX::" \
            | sort -V \
            | tail -1
    )
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
