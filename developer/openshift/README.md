# Pipelines Service in Openshift

## Description

This script essentially does this :

1. Install OpenShift GitOps on the cluster.
2. Set up cluster access by calling relevant scripts (scripts that generate credentials for the OpenShift cluster so it can be managed via gitops)
3. Install Pipelines Service on the cluster.

## Dependencies

Before installing the prerequisites, refer [DEPENDENCIES.md](../../DEPENDENCIES.md) to verify the versions of products, operators and tools used in Pipeline Service.

### Pre-requisites

Before you execute the script, you need:

1. to have a _kubernetes/openshift_ cluster with at least 6 CPU cores and 16GB RAM.
2. to install [oc](https://docs.openshift.com/container-platform/4.11/cli_reference/openshift_cli/getting-started-cli.html)
3. to install [argocd CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/)
4. to install [yq](https://mikefarah.gitbook.io/yq/#install)
5. to install [podman](https://github.com/containers/podman) or [docker](https://www.docker.com/). If you have both you can control which is used by setting the `CONTAINER_ENGINE` environment variable (e.g. `export CONTAINER_ENGINE="podman"`). While we do not recommend it for security reasons, you can prefix the binary with `sudo` to force the execution as the root user (e.g. `export CONTAINER_ENGINE="sudo podman"`).

You can run the `dev_setup.sh` script with or without parameters.

The [test.sh](../../operator/test/test.sh) script runs certain examples from tektoncd repo for pipelines and triggers. You can run the below script only after `dev_setup.sh` is run and the required resources are up and running.

```bash
./test.sh pipelines
    #Runs PipelineRun which sets and uses some env variables respectively.
    #https://github.com/tektoncd/pipeline/blob/main/examples/v1beta1/pipelineruns/using_context_variables.yaml

./test.sh triggers
    #Simulates a webhook for a Github PR which triggers a TaskRun
    #https://github.com/tektoncd/triggers/tree/main/examples/v1beta1/github

./test.sh pipelines triggers
    #Runs both tests
```

### Development - Onboarding a new component

This developer environment can be used to develop/test a new component on the Pipeline Service by changing parameters in [config.yaml](./config.yaml).
Considerations for testing a new component:-
1. We are deploying various applications using the GitOps approach and hence a user would need to change the values of `git_url` and `git_ref` to reflect their own Git repo.
2. A user can modify the applications to be deployed on the cluster by modifying [apps](./config.yaml).
3. Onboarding a new component requires creating a new Argo CD application in [argo-apps](../../operator/gitops/argocd/argo-apps/) and adding it to [kustomization.yaml](../../operator/gitops/argocd/argo-apps/kustomization.yaml).
4. For testing, users need to modify only the git source path and ref of their Argo CD application to reflect their own Git repo.

### Reset

One can reset its environement and all the resources deployed by dev scripts :-
```bash
developer/openshift/reset.sh --work-dir /path/to/my_dir
```
