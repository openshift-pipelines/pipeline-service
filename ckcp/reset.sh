#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

WORK_DIR="$SCRIPT_DIR/work"
KUBECONFIG_DIR="$WORK_DIR/kubeconfig"
KUBECONFIG_PLNSVC="$KUBECONFIG_DIR/plnsvc.clusteradmin.yaml"

usage() {
  echo "
Usage:
  ${0##*/} [options]

Reset all the configuration for pipelines service

Optional arguments:
  -p, --pipeline-cluster-kubeconfig
    Path to the kubeconfig file to the pipeline-cluster.
    Default: \"$KUBECONFIG\"
  -w, --workspace KCP_WORKSPACE
    Select the KCP workspace to log into.
    Default value: pln-svc
  -d, --debug
    Activate tracing/debug mode.
  -h, --help
    Display this message.

Example:
  ${0##*/} --all
" >&2
}

parse_args() {
  local args
  args="$(getopt -o dhp: -l "debug,help,pipeline-cluster-kubeconfig" -n "$0" -- "$@")"
  eval set -- "$args"
  while true; do
    case $1 in
    -p | --pipeline-cluster-kubeconfig)
      shift
      KUBECONFIG="$1"
      ;;
    -d | --debug)
      set -x
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

plnsvc_config() {
  KUBECONFIG="$KUBECONFIG_PLNSVC" "$@"
}

argocd_local() {
    mkdir -p "$WORK_DIR/argocd"
    argocd --config "$WORK_DIR/argocd" "$@"
}

user_confirm() {
  local answer
  local cluster_url
  cluster_url="$(plnsvc_config kubectl config view | yq ".clusters[0].cluster.server")"
  read -r -p "Are you sure you want to reset $cluster_url [y/N]: " answer
  case "$answer" in
  y | Y) ;;

  *)
    echo "[Abort]"
    exit 2
    ;;
  esac
}

reset_argocd() {
  echo "[ArgoCD]"

  echo -n "  - Removing applications: "
  for app in pipelines-controller pipelines-crds triggers-controller triggers-crds \
    triggers-interceptors; do
    if plnsvc_config argocd_local app get $app >/dev/null 2>&1; then
      plnsvc_config argocd_local app delete $app -y --cascade=false >/dev/null &
    fi
  done
  wait
  echo "OK"

  echo -n "  - Removing clusters: "
  # `argocd cluster rm` is failing with `permission denied`
  # The workaround is to delete the secret to the cluster
  for secret in $(
    plnsvc_config kubectl get secrets -n openshift-gitops |
      grep -E "^cluster-[^ ]+-[0-9]*" --only-matching
  ); do
    plnsvc_config kubectl delete secret "$secret" -n openshift-gitops --wait >/dev/null &
  done
  wait
  echo "OK"

  echo
}

reset_plnsvc() {
  echo "[Pipeline cluster]"

  echo -n "  - Removing KCP service account: "
  plnsvc_config kubectl delete -f "$SCRIPT_DIR/../kcp/manifests/kcp-manager.yaml" \
    --ignore-not-found --wait >/dev/null
  echo "OK"

  echo -n "  - Removing namespaces: "
  plnsvc_config kubectl delete -f "$SCRIPT_DIR/../kcp/manifests/pipeline-cluster.yaml" \
    --ignore-not-found --wait >/dev/null &
  for ns in $(
    plnsvc_config kubectl get ns | grep -E "^kcp[0-9a-z]{56}|ckcp" --only-matching |
      cut -d\  -f1
  ); do
    plnsvc_config kubectl delete namespace "$ns" --ignore-not-found --wait >/dev/null &
  done
  wait
  echo "OK"

  echo
}

main() {
  parse_args "$@"
  user_confirm
  reset_argocd
  reset_plnsvc
  rm -rf "$WORK_DIR"
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
