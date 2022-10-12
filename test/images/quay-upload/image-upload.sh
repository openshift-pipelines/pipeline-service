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
  printf "
Usage:
    %s [options]

Pull the latest tagged \$image for \$branch_name, tag it as \$commit_id,
and push it to the quay.io/\$registry repository.

The goal is to prevent building a new image when the contents have not
changed, and tag the previously built image with the new commit instead.

Optional arguments:
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    %s
" "${0##*/}" "${0##*/}" >&2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
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

init() {
  # fetching values from env vars
  username="$username"
  password="$password"
  registry="$registry"
  image="$image"
  image_path="$registry"/"$image"

  if [[ -z "$username" || -z "$password" || -z "$registry" || -z "$image" ]]; then
    printf "Error while fetching one of more env variables. Exiting.\n" >&2
    exit 1
  fi
}

get_commit_id() {
  if [ -n "$GITHUB_SHA" ]; then
    commit_id="${GITHUB_SHA:0:7}"
  fi
  if [ -z "$commit_id" ]; then
    printf "Commit ID not found" >&2
    exit 1
  fi
}

get_branch_name() {
  if [ -n "$GITHUB_REF" ]; then
    branch_name="$GITHUB_REF"
  fi
  if [ -z "$branch_name" ]; then
    printf "Branch name not found" >&2
    exit 1
  fi
}

pull_push_image() {
  source="$image_path":"$branch_name"
  target="$image_path":"$commit_id"

  podman login -u="$username" -p="$password" quay.io

  podman pull -q "$source"
  image=$(podman images "$source" --format json | jq '.[0].Names')
  if [[ "$image" == "null" ]]; then
    printf "Image '%s' was not pulled due to some issue. Exiting.\n" "$source" >&2
    exit 1
  fi

  podman tag "$source" "$target"

  podman push "$target"
}

main() {
  parse_args "$@"
  init
  get_branch_name
  get_commit_id
  pull_push_image
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
