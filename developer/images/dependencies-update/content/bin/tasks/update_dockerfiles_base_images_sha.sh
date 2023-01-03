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
# shellcheck source=developer/images/dependencies-update/content/bin/task.sh
source "$SCRIPT_DIR/../task.sh"

run_task() {
  echo "Update base images SHA in Dockerfiles" >"$COMMIT_MSG"
  process_dockerfiles
}

process_dockerfiles() {
  mapfile -t DOCKERFILES < <(
    find "$WORKSPACE_DIR" -type f -name Dockerfile |
      sed "s:$WORKSPACE_DIR/::" |
      grep --invert-match --extended-regexp "developer/exploration" |
      sort
  )
  while read -r from_base_image; do
    process_base_image_cmd
  done < <(grep --no-filename --regexp "^#@FROM " "${DOCKERFILES[@]}" | sort -u)
}

process_base_image_cmd() {
  base_image_name=$(echo "$from_base_image" | sed 's:^.* ::')
  echo -n "- $base_image_name"
  get_base_image_sha
  echo -n "@$base_image_sha : "
  update_base_image_sha
  if git diff --quiet; then
    echo "No update"
  else
    echo "Updated"
    echo "- Update base image SHA for '$base_image_name' to '$base_image_sha'" >>"$COMMIT_MSG"
    git add .
  fi
}

get_base_image_sha() {
  base_image_sha=$(skopeo inspect "docker://$base_image_name" --format="{{.Digest}}")
}

update_base_image_sha() {
  sed -i "s|^FROM  *$base_image_name@[^ ]*|FROM $base_image_name@$base_image_sha|" "${DOCKERFILES[@]}"
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
