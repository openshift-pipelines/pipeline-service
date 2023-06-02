# Purpose

This directory contains the manifests used to automate the installation of operators and other components leveraged by Pipeline Service on the workload clusters. It provides an opinionated approach to managing their configuration based on GitOps principles.

## Why GitOps?

We want to make the onboarding experience to use Pipeline Service as easy and customizable as possible. With that in mind, Pipeline Service is built around the principles of GitOps. Using kustomize, users will be able to set up, modify and update cluster resources without having to disrupt their existing setup. We provide base kustomization.yaml files to help get started, so that users can then add their customizations in the overlay/kustomization.yaml files.

## Dependencies

Before installing the prerequisites, refer [DEPENDENCIES.md](../../DEPENDENCIES.md) to verify the versions of products, operators and tools used in Pipeline Service.

## Components

Pipeline Service is composed of the following components, which can be deployed via `kustomize` or referenced in an ArgoCD application:

- `pipeline-service` - the core components that make up the service. Deploys the following:
  - OpenShift Pipelines operator
  - Pipelines as Code
  - Tekton Chains
  - Tekton Results
  - Tekton Metrics Exporter
- `grafana` - optional Grafana dashboard for monitoring.
