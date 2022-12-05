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

Update the sha of the base images in the Dockefiles.

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

process_dockerfiles() {
  mapfile -t DOCKERFILES < <(
    find "$PROJECT_DIR" -type f -name Dockerfile |
      sed "s:$PROJECT_DIR/::" |
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
  if grep --max-count=1 --quiet "FROM $base_image_name@$base_image_sha" "${DOCKERFILES[@]}"; then
    echo "No update"
  else
    update_base_image_sha
    echo "Updated to latest sha"
  fi
}

get_base_image_sha() {
  base_image_sha=$(skopeo inspect "docker://$base_image_name" | yq ".Digest")
}

update_base_image_sha() {
  sed -i "s|^FROM  *$base_image_name@.*|FROM $base_image_name@$base_image_sha|" "${DOCKERFILES[@]}"
  echo "- Update base image '$base_image_name' to '$base_image_sha'" >> "$COMMIT_MSG"
}

main() {
  if [ -n "${DEBUG:-}" ]; then
    set -x
  fi
  parse_args "$@"
  init
  process_dockerfiles
  echo "Done"
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
