#!/usr/bin/env bash

cd /workspace

KUBECONFIG=kubeconfig/admin.kubeconfig METRICS_DOMAIN=knative.dev/some-repository SYSTEM_NAMESPACE=tekton-pipelines KO_DATA_PATH=./pipeline/pkg/pod/testdata ./pipeline/bin/controller \
-kubeconfig-writer-image gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/kubeconfigwriter:v0.32.0 \
-git-image gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/git-init:v0.32.0 \
-entrypoint-image gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/entrypoint:v0.32.0 \
-nop-image gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/nop:v0.32.0 \
-imagedigest-exporter-image gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/imagedigestexporter:v0.32.0 \
-pr-image gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/pullrequest-init:v0.32.0 \
-gsutil-image gcr.io/google.com/cloudsdktool/cloud-sdk@sha256:27b2c22bf259d9bc1a291e99c63791ba0c27a04d2db0a43241ba0f1f20f4067f \
-shell-image registry.access.redhat.com/ubi8/ubi-minimal@sha256:54ef2173bba7384dc7609e8affbae1c36f8a3ec137cacc0866116d65dd4b9afe \
-shell-image-win mcr.microsoft.com/powershell:nanoserver@sha256:b6d5ff841b78bdf2dfed7550000fd4f3437385b8fa686ec0f010be24777654d6
