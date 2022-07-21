# kcp registration

The [images/kcp-registrar directory](../images/kcp-registrar) contains the logic used for registering workload clusters to kcp.

## Run

The registration is meant to be triggered from [Pipelines as Code](https://pipelinesascode.com/) and a [Tekton PipelineRun](../gitops/pac/.tekton/kcp-registration.yaml) is provided for the purpose in the .tekton directory.

Alternatively the registration can be performed by manually calling the registration script in the image directory:

```bash
KCP_ORG="root:pipelines-service" KCP_WORKSPACE="compute" KCP_SYNC_TAG="release-0.5" WORKSPACE_DIR="/workspace" ./register.sh
```

| Name | Description |
|------|-------------|
| KCP_ORG | contains the organistation for which the workload clusters need to be registered, i.e.: root:pipelines-service|
| KCP_WORKSPACE | contains the name of the workspace where the workload clusters get registered (created if it does not exist), i.e: compute|
| KCP_SYNC_TAG | the tag of the kcp syncer image to use (preset in the container image at build time and leveraged by the PipelineRun)|
| WORKSPACE_DIR | specifies the location of the cluster files<br> - a single file with extension kubeconfig is expected in the subdirectory: `gitops/credentials/kubeconfig/kcp`<br> - kubeconfig files for compute clusters are expected in the subdirectory: `gitops/credentials/kubeconfig/compute`|

## Authentication

The authentication to kcp and the workload clusters is done through the provided kubeconfig files.
