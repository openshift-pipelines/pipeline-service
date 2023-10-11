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

exit_error() {
  printf "\n[ERROR] %s\n" "$@" >&2
  printf "Exiting script.\n"
  exit 1
}

check_applications() {
  local ns="$1"
  shift
  local applications=("$@")

  for app in "${applications[@]}"; do
    printf -- "- %s: " "$app"

    # Check if the ArgoCD application exists
    if ! timeout 300s bash -c "while ! kubectl get application/$app -n $ns >/dev/null 2>/dev/null; do printf '.'; sleep 10; done"; then
      printf "%s not found (timeout)\n" "$app"
      kubectl get application/"$app" -n "$ns"
      export INSTALL_FAILED=1
      return
    else
      printf "Exists"
    fi

    # Check if the ArgoCD application is synced
    if kubectl wait --for=jsonpath="{.status.sync.status}"="Synced" "application/$app" -n "$ns" --timeout=600s >/dev/null; then
      printf ", Synced"
      if kubectl wait --for=jsonpath="{.status.health.status}"="Healthy" "application/$app" -n "$ns" --timeout=600s >/dev/null; then
        printf ", Healthy\n"
      else
        printf ", Unhealthy\n"
        kubectl -n "$ns" describe "application/$app"
      fi
    else
      printf ", OutOfSync\n"
      kubectl -n "$ns" describe "application/$app"
    fi
  done
}

check_subscriptions() {
  local ns="$1"
  shift
  local subscriptions=("$@")

  for sub in "${subscriptions[@]}"; do
    printf -- "- %s: " "$sub"

    # Check if the OLM Subscription exists
    if ! timeout 300s bash -c "while ! kubectl get subscription/$sub -n $ns >/dev/null 2>/dev/null; do printf '.'; sleep 10; done"; then
      printf "%s not found (timeout)\n" "$sub"
      kubectl get subscription/"$sub" -n "$ns"
      export INSTALL_FAILED=1
      return
    else
      printf "Exists"
    fi

    # Check if the OLM Subscription is at the latest known version
    if kubectl wait --for=jsonpath="{.status.state}"="AtLatestKnown" "subscription/$sub" -n "$ns" --timeout=600s >/dev/null; then
      printf ", AtLatestKnown\n"
    else
      printf ", NotUpdated\n"
      kubectl -n "$ns" describe "subscription/$sub"
    fi
  done
}

check_deployments() {
  local ns="$1"
  shift
  local deployments=("$@")

  for deploy in "${deployments[@]}"; do
    printf -- "- %s: " "$deploy"

    # Check if the deployment exists
    if ! timeout 300s bash -c "while ! kubectl get deployment/$deploy -n $ns >/dev/null 2>/dev/null; do printf '.'; sleep 10; done"; then
      printf "%s not found (timeout)\n" "$deploy"
      kubectl get deployment/"$deploy" -n "$ns"
      kubectl -n "$ns" get events | grep Warning
      export INSTALL_FAILED=1
      return
    else
      printf "Exists"
    fi

    # Check if the deployment is Available and Ready
    if kubectl wait --for=condition=Available=true "deployment/$deploy" -n "$ns" --timeout=200s >/dev/null; then
      printf ", Ready\n"
    else
      kubectl -n "$ns" describe "deployment/$deploy"
      kubectl -n "$ns" logs "deployment/$deploy"
      kubectl -n "$ns" get events | grep Warning
      exit 1
    fi
  done
}

check_crashlooping_pods() {
  local ns="$1"
  local crashlooping_pods

  printf -- "- Check for crashlooping pods in namespace %s: " "$ns"
  crashlooping_pods=$(kubectl get pods -n "$ns" --field-selector=status.phase!=Running -o jsonpath='{range .items[?(@.status.containerStatuses[*].state.waiting.reason=="CrashLoopBackOff")]}{.metadata.name}{","}{end}' 2>/dev/null)

  # Check if the any crashlooping pods found
  if [[ -n $crashlooping_pods ]]; then
    printf "Error\n"
    IFS=',' read -ra pods <<< "$crashlooping_pods"
    for pod in "${pods[@]}"; do
      kubectl get pod "$pod" -n "$ns"
      kubectl logs "$pod" -n "$ns"
    done
    exit 1
  else
    printf "OK\n"
  fi
}

check_statefulsets() {
  local ns="$1"
  shift
  local statefulsets=("$@")

  for statefulset in "${statefulsets[@]}"; do
    printf -- "- %s: " "$statefulset"

    # Check if the statefulset exists
    if ! timeout 300s bash -c "while ! kubectl get statefulset/$statefulset -n $ns >/dev/null 2>/dev/null; do printf '.'; sleep 10; done"; then
      printf "%s not found (timeout)\n" "$statefulset"
      kubectl get statefulset/"$statefulset" -n "$ns"
      kubectl -n "$ns" get events | grep Warning
      export INSTALL_FAILED=1
      return
    else
      printf "Exists"
    fi

    # Check if the statefulset has available replica
    if kubectl wait --for=jsonpath='{.status.availableReplicas}'=1 "statefulset/$statefulset" -n "$ns" --timeout=200s >/dev/null; then
      printf ", Ready\n"
    else
      kubectl -n "$ns" describe "statefulset/$statefulset"
      kubectl -n "$ns" logs "statefulset/$statefulset"
      kubectl -n "$ns" get events | grep Warning
      exit 1
    fi
  done
}

indent () {
  offset="${1:-2}"
  sed "s/^/$(printf "%${offset}s")/"
}
