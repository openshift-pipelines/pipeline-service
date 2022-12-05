#!/usr/bin/env bash

# Copyright 2022 The Pipeline Service Authors.
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

Update the kcp version.

Optional arguments:
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/}
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
  if [ -z "${PROJECT_DIR:-}" ]; then
    echo "[ERROR] Unset variable: PROJECT_DIR" >&2
    exit 1
  fi
}

get_current_version() {
  # shellcheck source=shared/config/dependencies.sh
  source "$PROJECT_DIR/shared/config/dependencies.sh"
  current_kcp_version="${KCP_VERSION:-}"
  if [ -z "$current_kcp_version" ]; then
    printf "[ERROR] Could not retrieve the current kcp version\n" >&2
    exit 1
  fi
}

get_latest_version() {
  latest_kcp_version="$(curl -s https://api.github.com/repos/kcp-dev/kcp/releases/latest | yq '.tag_name' | sed 's/v//')"
  if [ -z "$latest_kcp_version" ]; then
    printf "[ERROR] Could not retrieve the latest kcp version\n" >&2
    exit 1
  fi
}

update_kcp_version() {
  printf "Upgrade kcp version from '%s' to '%s'\n" "$current_kcp_version" "$latest_kcp_version" | tee "$COMMIT_MSG"
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" "$PROJECT_DIR/.github/workflows/build-push-images.yaml"
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" "$PROJECT_DIR/.github/workflows/local-dev-ci.yaml"
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" "$PROJECT_DIR/developer/ckcp/config.yaml"
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" "$PROJECT_DIR/developer/ckcp/openshift/overlays/dev/kustomization.yaml"
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" "$PROJECT_DIR/operator/docs/kcp-registration.md"
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" "$PROJECT_DIR/operator/images/kcp-registrar/content/bin/register.sh"
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" "$PROJECT_DIR/shared/config/dependencies.sh"
}

main() {
  if [ -n "${DEBUG:-}" ]; then
    set -x
  fi
  parse_args "$@"
  init
  get_current_version
  get_latest_version

  if [ "$current_kcp_version" != "$latest_kcp_version" ]; then
    update_kcp_version
  else
    printf "Already on the latest version: '%s'.\n" "$current_kcp_version"
  fi
  echo "Done"
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
