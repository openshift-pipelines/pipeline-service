# Purpose

This directory contains the manifests used to automate the installation of operators and other components leveraged by Pipelines-service on the workload clusters. It provides an opinionated approach of managing their configuration based on GitOps principles.

## Why GitOps?

We want to make the onboarding experience to use Pipelines-service as easy and customizable as possible. With that in mind, Pipelines-service is built around the principles of GitOps. Using kustomize, users will be able to set up, modify and update cluster resources without having to disrupt their existing setup. We provide base kustomization.yaml files to help get started, so that users can then add their customizations in the overlay/kustomization.yaml files.

## Pre-requisites
- Openshift cluster
- Openshift GitOps operator installed (instructions [here](https://docs.openshift.com/container-platform/4.10/cicd/gitops/installing-openshift-gitops.html))
- Pipelines as Code installed and setup to talk to this repo  (instructions [here](./pac/README.md) and [here](https://pipelinesascode.com/docs/install/installation/))

## Components

Following the Phase 1 architecture described [here](../docs/images/phase1.png), we structured GitOps to set up an OpenShift cluster, i.e., 
- Install pipelines and triggers components on the physical cluster via GitOps Application.
- Log into kcp, register the clusters using the credentials for accessing kcp shared instance.

Post this, a user will be able to log in to kcp workspace and start creating PipelineRuns :)

## How to run

Currently, we support two ways to get the cluster set up and ready to start creating PipelineRuns:  
a. Run the script manually 
b. Merge a PR with the kubeconfigs and overlay kustomization to trigger a PipelineRun to automate the process.

1. Run scripts 

    a. To install pipelines and triggers 
    ```
    WORKSPACE_DIR=/home/workspace/pipelines-service ../images/cluster-setup/install.sh
    ```
    
    b. To access and setup kcp
    ```
    KCP_ORG="root:pipelines-service" KCP_WORKSPACE="compute" DATA_DIR="/home/workspace/pipelines-service" ../images/kcp-registrar/register.sh
    ```

2. Open and merge a Pull Request
There are a couple of steps that need to be done in order to use PAC in Pipelines-service.
a. Install Pipelines as Code on the OpenShift Cluster.
b. Set up a Git application on any of the Git providers (GitHub, GitLab, Bitbucket etc.) by following the steps from [here](https://pipelinesascode.com).

Once the above two steps are done, the GitHub app (or any other Git provider app) you've setup from step 2 is now talking to PAC and would watch PRs and trigger PipelineRuns that automates the workflow previously described.

The PR should have:
- kubeconfig/s of the OpenShift clusters to be placed under gitops/credentials/kubeconfig/compute
- overlay/kustomization.yaml to be created under gitops/environment/compute/<clustername>/overlay/kustomization.yaml
