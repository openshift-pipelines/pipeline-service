# Continuous integration tests

After installing the GitHub Application, Pipelines as Code triggers the PipelineRuns in [.tekton](../../.tekton) which execute the test tasks for each PR on the `prd-rh01` cluster, in the `tekton-ci` namespace, before merging it.

All the functional tests run on a ROSA HCP cluster that is automatically provisionned during the pipeline execution.

## Setup GitHub app

- The repository needs to install the [Red Hat Trusted App Pipeline](https://github.com/apps/red-hat-trusted-app-pipeline) GitHub Application, so that Pipelines as Code is triggered on repository events.

## How to configure ROSA HCP

ROSA with HCP official [Documentation Guide](https://docs.openshift.com/rosa/rosa_hcp/rosa-hcp-sts-creating-a-cluster-quickly.html).

### Pre-requisites:

- Install [aws](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) cli
- Install [rosa](https://docs.openshift.com/rosa/rosa_cli/rosa-get-started-cli.html) cli
- Install [terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) cli

### ROSA with HCP Prerequisites
To create a ROSA with HCP cluster, you can create the following items by running the [rosa_hcp_setup.sh](../hack/rosa_hcp_setup.sh) script.

* A configured virtual private cloud (VPC)

* Account-wide roles

* An OIDC configuration

* Operator roles

After that, you need to add a Secret for storing the Bitwarden credentials(BW_CLIENTID,BW_CLIENTSECRET and BW_PASSWORD). 

## Debugging an issue during the CI execution
The CI will destroy the test cluster at the end of the pipeline by default.
This is an issue when troubleshooting is required.

To bypass deletion of the test cluster, delete the `destroy-cluster.txt` file in created in the root of the cloned repository.
There is a 15 minutes window to log onto the container running the `destroy-cluster` step and delete the file.

### Login to the ROSA with HCP cluster
When the test cluster is remained, to access the test cluster, you can go to the task named `deploy-cluster` to find the content of kubeconfig and login username/password.  

### Debugging the run-plnsvc-setup task
When the CI failed during the run-plnsvc-setup task, you can ssh to the ci-runner container in the test cluster to manually execute `dev_setup.sh` to debug the task. For example

```
$ oc -n default rsh pod/ci-runner
$ export KUBECONFIG=/kubeconfig
$ /source/developer/openshift/dev_setup.sh --debug --use-current-branch --force --work-dir /source/developer/openshift/work
```
