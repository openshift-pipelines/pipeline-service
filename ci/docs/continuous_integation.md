# Continuous integration tests

Pipelines as Code triggers the PipelineRuns in [.tekton](../../.tekton) which execute the test tasks for each PR, before merging it.

All the functional tests run on a HyperShift AWS cluster.

## How to configure HyperShift

HyperShift official [Documentation Guide](https://hypershift-docs.netlify.app/).

### Pre-requisites:

- Install [aws](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) cli
- Install [hypershift](https://hypershift-docs.netlify.app/getting-started/#prerequisites) cli
- Provision a ROSA cluster by following [documentation](rosa_cluster_provision.md)

### HyperShift Setup
You can configure HyperShift on ROSA by running the [hypershift_setup.sh](../hack/hypershift_setup.sh) script.

After that, you need to add a Configmap for storing the kubeconfig of ROSA cluster and a Secret for sotring the Bitwarden credentials(BW_CLIENTID,BW_CLIENTSECRET and BW_PASSWORD). 

## Setup GitHub app

- Need to configure GitHub app for Pipelines as Code configuration into Pipeline Service repository.

## Debugging an issue during the CI execution
The CI will destroy the test cluster at the end of the pipeline by default.
This is an issue when troubleshooting is required.

To bypass deletion of the test cluster, delete the `destroy-cluster.txt` file in created in the root of the cloned repository.
There is a 15 minutes window to log onto the container running the `destroy-cluster` step and delete the file.
