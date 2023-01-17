# Continuous integration tests

Pipelines as Code triggers the PipelineRuns in [.tekton](../../.tekton) which execute the test tasks for each PR, before merging it.

All the functional tests run on a HyperShift AWS cluster.

## How to configure HyperShift

HyperShift official [Documentation Guide](https://hypershift-docs.netlify.app/).

### Pre-requisites:

- Install [bw](https://bitwarden.com/help/cli/) cli
- Install [aws](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) cli
- Provision a ROSA cluster by following [documentation](rosa_cluster_provision.md)

### HyperShift Setup

You can configure HyperShift on ROSA by running the [hypershift_setup.sh](../hack/hypershift_setup.sh) script.

## Setup GitHub app

- Need to configure GitHub app for Pipelines as Code configuration into Pipeline Service repository.

## Bitwarden secrets

We import our HyperShift secrets like pull-secret, public and private key pair, compute kubeconfig and base domain url to Bitwarden.
To access those secrets, you need to have a Red Hat verified account. If do not have one then follow [Account Setup](https://redhat.service-now.com/help?id=kb_article&sys_id=28b1450e975fd9102f8d361e6253af65) documentation to signup.