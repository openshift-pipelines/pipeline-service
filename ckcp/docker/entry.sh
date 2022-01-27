#!/usr/bin/env bash

rm -rf .kcp/
./kcp/bin/kcp start \
  --push-mode=true \
  --pull-mode=false \
  --install-cluster-controller \
  --install-workspace-controller \
  --auto-publish-apis \
  --resources-to-sync="deployments.apps,pods,services"