#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"
PROJECT_DIR="$(
  cd "$SCRIPT_DIR/../.." >/dev/null || exit 1
  pwd
)"
export PROJECT_DIR

parse_args() {
  mapfile -t DEFAULT_IMAGE_DIRS < <(
    find "$PROJECT_DIR" -type f -name Dockerfile -exec dirname {} \; |
      sed "s:$PROJECT_DIR/::" |
      grep --invert-match --extended-regexp "/developer/exploration/|.devcontainer" |
      sort
  )
  IMAGE_DIRS=()
  while [[ $# -gt 0 ]]; do
    case $1 in
    --delete)
      DELETE_IMAGE="1"
      ;;
    -i | --image)
      shift
      if [ ! -d "$1" ]; then
        echo "[ERROR] Directory does not exists: $1" >&2
        exit 1
      else
        if [ ! -e "$1/Dockerfile" ]; then
          echo "[ERROR] Dockerfile not found in '$1'" >&2
          exit 1
        fi
      fi
      IMAGE_DIRS+=("$1")
      ;;
    -t | --tag)
      shift
      TAG="$1"
      ;;
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
  TAG=${TAG:-latest}
  if [ -z "${IMAGE_DIRS[*]}" ]; then
    IMAGE_DIRS=("${DEFAULT_IMAGE_DIRS[@]}")
  fi
  buildah="buildah --storage-driver=vfs"
}

build_image() {
  image_name=$(basename "$image_dir")
  case "$image_name" in
  quay-upload|vulnerability-scan)
    context="$image_dir"
    ;;
  *)
    context="$PROJECT_DIR"
    ;;
  esac

  $buildah build --format=oci \
    --log-level debug \
    --tls-verify=true --no-cache \
    -f "$image_dir/Dockerfile" --tag "$image_name:$TAG" "$context"
}

delete_image() {
  image_name="localhost/$(basename "$image_dir")"
  if $buildah images "$image_name:$TAG"; then
    $buildah rmi "$image_name:$TAG"
  fi
}

main() {
  if [ -n "${DEBUG:-}" ]; then
    set -x
  fi
  parse_args "$@"
  init
  for image_dir in "${IMAGE_DIRS[@]}"; do
    echo "[$image_dir]"
    build_image
    if [ -n "${DELETE_IMAGE:-}" ]; then
      delete_image
    fi
    echo
  done
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
