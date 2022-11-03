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

CONFIG="$(dirname "$(dirname "$SCRIPT_DIR")")/developer/ckcp/config.yaml"
current_kcp_version="$(yq '.kcp.version' "$CONFIG" | sed 's/v//' )"

latest_kcp_version="$(curl -s https://api.github.com/repos/kcp-dev/kcp/releases/latest | yq '.tag_name' | sed 's/v//' )"

if [ "$latest_kcp_version" == "" ] || [ "$current_kcp_version" == "" ]; then
  printf "[ERROR] Could not retrieve kcp version: current='%s' latest='%s'" "${current_kcp_version:-not found}" "${latest_kcp_version:-not found}" >&2
  exit 1
fi

if [ "$current_kcp_version" != "$latest_kcp_version" ]; then
  printf "\nUpgrading kcp version from '%s' to '%s'\n"  "$current_kcp_version" "$latest_kcp_version"
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" .github/workflows/build-push-images.yaml
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" .github/workflows/local-dev-ci.yaml
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" DEPENDENCIES.md
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" developer/ckcp/openshift/overlays/dev/kustomization.yaml
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" architect/docs/kcp-registration.md
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" operator/images/access-setup/Dockerfile
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" operator/images/kcp-registrar/Dockerfile
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" operator/images/kcp-registrar/bin/register.sh
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" developer/ckcp/config.yaml
  sed -i "s,$current_kcp_version,$latest_kcp_version,g" shared/config/dependencies.yaml
  echo "$latest_kcp_version" > /tmp/kcp-upgrade.txt
else
  printf "\nAlready on the latest version: '%s'.\n" "$current_kcp_version"
fi
