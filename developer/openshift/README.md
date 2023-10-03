# Pipelines Service in Openshift

## Description

This script essentially does this :

1. Install OpenShift GitOps on the cluster.
1. Deploy Pipelines Service on the cluster via an ArgoCD application.

## Dependencies

Before installing the prerequisites, refer [DEPENDENCIES.md](../../DEPENDENCIES.md) to verify the versions of products, operators and tools used in Pipeline Service.

### Pre-requisites

Before you execute the script, you need:

1. to have an OpenShift cluster with at least 6 CPU cores and 16GB RAM.
1. to install [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
1. to install [oc](https://docs.openshift.com/container-platform/4.11/cli_reference/openshift_cli/getting-started-cli.html)
1. to install [argocd CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/)
1. to install [yq](https://mikefarah.gitbook.io/yq/#install)

You can run the `dev_setup.sh` script with or without parameters.
The `--use-current-branch` parameter should be used when testing manifests changes.

The [test.sh](../../operator/test/test.sh) script runs certain examples from tektoncd repo for pipelines. You can run the below script only after `dev_setup.sh` is run and the required resources are up and running.

```bash
./test.sh --test pipelines
    # Runs a minimal PipelineRun
    # Checks that the pipelinerun is successful.

./test.sh --test chains
    # Simulates the creation of an image
    # Checks that the pipeline and image are signed.
    # Checks that the key to decode the signed data is available to all users.

./test.sh --test results
    # Checks that logs are uploaded by tekton-results.
```

### Development - Onboarding a new component

This developer environment can be used to develop/test a new component on the Pipeline Service by changing parameters in [config.yaml](./config.yaml).
Considerations for testing a new component:
1. We are deploying various applications using the GitOps approach and hence a user would need to change the values of `git_url` and `git_ref` to reflect their own Git repository.
2. A user can modify the applications to be deployed on the cluster by modifying the [apps field](./config.yaml).
3. Onboarding a new component requires creating a new Argo CD application in [argo-apps](../../operator/gitops/argocd/argo-apps/) and adding it to [kustomization.yaml](../../operator/gitops/argocd/argo-apps/kustomization.yaml).
4. For testing, users need to modify only the git source path and ref of their Argo CD application to reflect their own Git repo.

### Reset

One can reset its environment and all the resources deployed by dev scripts:

```bash
developer/openshift/reset.sh --work-dir /path/to/my_dir
```
