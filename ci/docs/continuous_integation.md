# Continuous integration tests

Pipelines as Code triggers the PipelineRuns in [.tekton](../../.tekton) which execute the test tasks for each PR, before merging it.

All the functional tests run on a HyperShift AWS cluster.

## How to configure HyperShift

HyperShift official [Documentation Guide](https://hypershift-docs.netlify.app/).

### Pre-requisites:

- Install [aws](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) cli
- Provision a ROSA cluster by following [documentation](rosa_cluster_provision.md)

### HyperShift Setup

You can configure HyperShift on ROSA by running the [hypershift_setup.sh](../hack/hypershift_setup.sh) script.

## Setup GitHub app

- Need to configure GitHub app for Pipelines as Code configuration into Pipeline Service repository.
