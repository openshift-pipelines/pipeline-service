# Pipelines as Code

## Goal

[Pipelines as Code](https://pipelinesascode.com/) can be leveraged for automating the registration of new clusters to Argo CD and kcp following a GitOps approach.
When a kubeconfig file gets added to a GitOps repository Pipelines as Code triggers a pipeline for the purpose. It is similar in this respect to GitHub actions and a git provider independent alternative to it.

---
**_NOTE:_**  Pipelines as Code can leverage any cluster for running its pipelines. The cluster does not have to be part of the Pipelines Service infrastructure.

---

## Instalation and runner registration

This directory contains the manifests used for installing Pipelines as Code and registering the runners.

Pipelines as Code comes pre-installed with the OpenShit Pipelines Operator. This is what should be used for its [installation on OpenShift](https://docs.openshift.com/container-platform/4.10/cicd/pipelines/installing-pipelines.html).
The runner registration still needs to be done if it hasn't already.

A webhook and credentials need to be added on the provider side of the git repository. Follow the [Pipelines as Code instructions](https://pipelinesascode.com/docs/install/) specific to your provider for the purpose. 

A script has been made available in this directory for automating the cluster (runner) side. It accepts the following parameters:

- KUBECONFIG: the path to the kubeconfig file used to connect to the cluster where Pipelines as Code will be installed
- GITOPS_REPO: the repository for which Pipelines as Code needs to be set up
- GIT_TOKEN: personal access token to the git repository
- WEBHOOK_SECRET: secret configured on the webhook used to validate the payload
- CONTROLLER_INSTALL (optional): the controller will be installed only if it is set to true. Pipelines as Code are installed together with the OpenShift Pipelines operator
- PAC_HOST (optional): Hostname for the Pipelines as Code ingress if CONTROLLER_INSTALL=true has been set


The registration can be performed by running for instance:

```console
KUBECONFIG="/pathto/kubeconfig" GITOPS_REPO="https://gitops.org.com/org/pipelines-service-infra" GIT_TOKEN="s2sdfdsf3EFfd42fFSfsg4ds" WEBHOOK_SECRET="b3erewer43a44eerwsafdfasf11cd37" ./setup.sh
```

## Pipelines

A pipeline for the registration of new clusters to ArgoCD and kcp will shortly be made available.
