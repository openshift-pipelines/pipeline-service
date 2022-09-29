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

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

CONFIG="$(dirname "$(dirname "$SCRIPT_DIR")")/config/config.yaml"
current_kcp_version="$(yq '.version.kcp' "$CONFIG" | sed 's/v//' )"

latest_kcp_version="$(curl -s https://api.github.com/repos/kcp-dev/kcp/releases/latest | yq '.tag_name' | sed 's/v//' )"

if [[ -z "$latest_kcp_version" ]] || [[ -z "$current_kcp_version" ]]; then
  printf "Something went wrong." >&2
  exit 1
fi

if [[ "$current_kcp_version" != "$latest_kcp_version" ]]; then
  printf "\nNew kcp version is found: %s\n" "$latest_kcp_version"
  printf "\nUpgrading kcp version from '%s' to '%s'\n"  "$current_kcp_version" "$latest_kcp_version"
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" .github/workflows/build-push-images.yaml
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" .github/workflows/local-dev-ci.yaml
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" DEPENDENCIES.md
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" ckcp/openshift/overlays/dev/kustomization.yaml
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" docs/kcp-registration.md
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" images/kcp-registrar/Dockerfile
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" images/kcp-registrar/register.sh
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" config/config.yaml
else
  printf "\nNo new kcp version is found, already on latest version.\n"
  exit 0
fi
