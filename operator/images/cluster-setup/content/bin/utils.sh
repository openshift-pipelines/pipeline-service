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

check_deployments() {
  local ns="$1"
  shift
  local deployments=("$@")

  for deploy in "${deployments[@]}"; do
    printf -- "- %s: " "$deploy"

    #a loop to check if the deployment exists
    if ! timeout 300s bash -c "while ! kubectl get deployment/$deploy -n $ns >/dev/null 2>/dev/null; do printf '.'; sleep 10; done"; then
      printf "%s not found (timeout)\n" "$deploy"
      kubectl get deployment/"$deploy" -n "$ns"
      kubectl -n "$ns" get events | grep Warning
      exit 1
    else
      printf "Exists"
    fi

    #a loop to check if the deployment is Available and Ready
    if kubectl wait --for=condition=Available=true "deployment/$deploy" -n "$ns" --timeout=100s >/dev/null; then
      printf ", Ready\n"
    else
      kubectl -n "$ns" describe "deployment/$deploy"
      kubectl -n "$ns" logs "deployment/$deploy"
      kubectl -n "$ns" get events | grep Warning
      exit 1
    fi
  done
}

check_pod_by_label() {
  local ns="$1"
  local label="$2"

  printf -- "- pod with label %s: " "$label"

  #a loop to check if the pod exists
  local numOfAttempts=40
  local i=0
  while [ -z "$(kubectl get pods -l "$label" -n "$ns" --no-headers -o custom-columns=':metadata.name')" ]; do
    printf '.'; sleep 5;
    i=$((i+1))
    if [[ $i -eq "${numOfAttempts}" ]]; then
      printf "\n[ERROR] Pod %s not found by timeout \n" "$label" >&2
      kubectl -n "$ns" get events | grep Warning
      exit 1
    fi
  done

  printf "Exists"

  #a loop to check if the pod is Available and Ready
  if kubectl wait --for=condition=ready pod -l "$label" -n "$ns" --timeout=100s >/dev/null; then
    printf ", Ready\n"
  else
    printf "\n[ERROR] Pod %s failed to start\n" "$label" >&2
    kubectl -n "$ns" describe pod -l "$label" 
    kubectl -n "$ns" logs -l "$label" 
    kubectl -n "$ns" get events | grep Warning
    exit 1
  fi
}

fetch_bitwarden_secrets() {
  CREDENTIALS_DIR="$WORKSPACE_DIR/credentials"
  BITWARDEN_CRED="$CREDENTIALS_DIR/secrets/bitwarden.yaml"

  setx_off
  BW_CLIENTID="${BW_CLIENTID:-}"
  BW_CLIENTSECRET="${BW_CLIENTSECRET:-}"
  BW_PASSWORD="${BW_PASSWORD:-}"
  setx_on

  if [ ! -e "$BITWARDEN_CRED" ]; then
    echo "No BW secrets"
    return
  fi

  printf "[Bitwarden]:\n"
  printf "bitwarden config file found at '%s'.\n" "$BITWARDEN_CRED" | indent 2
  setx_off
  if [ -z "$BW_CLIENTID" ]; then
      printf "Error: BW_CLIENTID is unset.\n" >&2 | indent 2
      exit 1
  fi
  if [ -z "$BW_PASSWORD" ]; then
      printf "Error: BW_PASSWORD is unset.\n" >&2 | indent 2
      exit 1
  fi
  setx_on

  printf "bitwarden credentials: OK\n" | indent 2
  if [ "$(bw logout >/dev/null 2>&1)$?" -eq 0 ]; then
    printf "Logout successful.\n" >/dev/null
  fi
  if (setx_off; BW_CLIENTID="$BW_CLIENTID" BW_CLIENTSECRET="$BW_CLIENTSECRET" bw login --apikey >/dev/null 2>&1); then
    printf "Login successful.\n" >/dev/null
  fi

  login_status=$(bw login --check 2>&1)
  if [ "$login_status" = "You are not logged in." ]; then
    printf "Error while logging into Bitwarden.\n" >&2 | indent 2
    return
  fi

  setx_off
  session=$(BW_PASSWORD="$BW_PASSWORD" bw unlock --passwordenv BW_PASSWORD --raw)
  setx_on

  # process id/path pairs from bitwarden.yaml
  secret_count=$(yq '.credentials | length' "$BITWARDEN_CRED")
  for i in $(seq 0 "$((secret_count-1))"); do
    id="$(yq ".credentials[$i].id" "$BITWARDEN_CRED")"
    cred_path="$WORKSPACE_DIR/$(yq ".credentials[$i].path" "$BITWARDEN_CRED")"

    if ! mkdir -p "$(dirname "$cred_path")"; then
      printf "Unable to create '%s'.\n" "$(dirname "$cred_path")" >&2 | indent 2
      exit 1
    fi
    if ! (setx_off; bw get password "$id" --session "$session" | base64 -d > "$cred_path" ); then
      printf "Unable to copy the contents of '%s' to '%s'. Exiting.\n" "$id" "$cred_path" >&2 | indent 2
      exit 1
    fi
    printf "Extracted secret with the ID '%s' to '%s'.\n" "$id" "$cred_path" | indent 2
  done
  printf "Extraction completed.\n" | indent 2
}

indent () {
        sed "s/^/$(printf "%$1s")/"
}

# turns off tracing even with set -x mode enabled across the script to prevent secrets leaking
setx_off() {
  set +x
}

# turns on tracing
setx_on() {
  if [ -n "$DEBUG" ]; then
    set -x
  fi
}
