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

usage_args() {
  echo "
Optional arguments:
    -k, --kubeconfig_dir KUBECONFIG_DIR
        Path to the directory holding the kubeconfigs. The directory must contain the
        files ['argocd.yaml', 'kcp.yaml', 'plnsvc.yaml'] and the user must be logged in.
        Default value: ${KUBECONFIG:-$HOME/.kube}
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/} --all
" >&2
}

_parse_args() {
  DEBUG=" "

  local args
  args="$(getopt -o dhe:k:w: -l "debug,help,environment,kcp,workspace" -n "$0" -- "$@")"
  eval set -- "$args"
  while true; do
    case "$1" in
    -k | --kubeconfig_dir)
      shift
      KUBECONFIG_DIR=$1
      ;;
    -d | --debug)
      set -x
      DEBUG="-d"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      # End of arguments
      break
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

_init_work_dir() {
  WORK_DIR="${WORK_DIR:-$SCRIPT_DIR/work}"
  KUBECONFIG_DIR="${KUBECONFIG_DIR:-$WORK_DIR/kubeconfig}"

  if [ ! -d "$KUBECONFIG_DIR" ]; then
      echo "Configuration not found in: $KUBECONFIG_DIR" >&2
      echo "" >&2
      usage
      exit 1
  fi

  mkdir -p "$WORK_DIR/kubeconfig"
  if [ "$WORK_DIR/kubeconfig" != "$KUBECONFIG_DIR" ]; then
    for kubeconfig in argocd kcp plnsvc; do
      cp "$KUBECONFIG_DIR/$kubeconfig.yaml" "$WORK_DIR/kubeconfig/"
    done
  fi

  for kubeconfig in argocd kcp plnsvc; do
      if [ ! -e "$KUBECONFIG_DIR/$kubeconfig.yaml" ]; then
        echo "Missing configuration for $kubeconfig in '$KUBECONFIG_DIR'" >&2
        echo "" >&2
        usage
        exit 1
      fi
  done

  KUBECONFIG_DIR="$WORK_DIR/kubeconfig"
  KUBECONFIG_ARGOCD="$KUBECONFIG_DIR/argocd.yaml"
  KUBECONFIG_KCP="$KUBECONFIG_DIR/kcp.yaml"
  KUBECONFIG_PLNSVC="$KUBECONFIG_DIR/plnsvc.yaml"
}

parse_init(){
  _parse_args "$@"
  _init_work_dir
}

argocd_local() {
  argocd --config "$KUBECONFIG_ARGOCD" "$@"
}

kcp_config() {
  KUBECONFIG="$KUBECONFIG_KCP" "$@"
}

plnsvc_config() {
  KUBECONFIG="$KUBECONFIG_PLNSVC" "$@"
}
