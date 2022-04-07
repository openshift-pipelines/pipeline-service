#!/usr/bin/env bash

rm -rf .kcp/
./kcp/bin/kcp start \
  --push-mode=true \
  --pull-mode=false \
  --run-controllers \
  --auto-publish-apis \
  --resources-to-sync="deployments.apps,statefulsets.apps,services,secrets,persistentvolumeclaims"