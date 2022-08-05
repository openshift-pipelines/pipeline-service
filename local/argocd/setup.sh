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

# Usage: KUBECONFIG="path-to-kubeconfig" ./setup.sh

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
pushd "$parent_path"

printf "Installing Argo CD\n"

kubectl --kubeconfig "${KUBECONFIG}" create namespace argocd
kubectl --kubeconfig "${KUBECONFIG}" apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
i=0
while ! kubectl --kubeconfig "${KUBECONFIG}" wait deployments ingress-nginx-controller -n ingress-nginx --for=jsonpath='{.status.availableReplicas}'=1 --timeout=5s; do
	sleep 60
	i=$((i+1))
	if [ $i -gt 60 ]; then
		printf "Ingress deployment not ready in time\n"
		exit 1
	fi
done
kubectl --kubeconfig "${KUBECONFIG}" apply -f ingress.yaml

printf "Argo CD installed\n"

popd
