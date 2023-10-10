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
To create a ROSA with HCP cluster, you have to create the following items. This is a one-time setup.

#### A configured virtual private cloud (VPC)

```
$ mkdir hypershift-tf
$ cd hypershift-tf
$ curl -s -o setup-vpc.tf https://raw.githubusercontent.com/openshift-cs/OpenShift-Troubleshooting-Templates/master/rosa-hcp-terraform/setup-vpc.tf
$ terraform init
$ terraform plan -out rosa.tfplan -var aws_region=us-east-1 -var cluster_name=plnsvc-ci
$ terraform apply rosa.tfplan
```

#### Account-wide roles
Log in to your RedHat account

```
$ rosa login --token="<your-rosa-token,find this token at https://console.redhat.com/openshift/token/rosa >"
```

Create the account-wide STS roles and policies

```
% rosa create account-roles --prefix <prefix-name> --mode auto -y --version 4.13
```

#### An OIDC configuration

```
% rosa create oidc-config --mode auto --managed --yes
```

#### Operator roles

```
% rosa create operator-roles --prefix <prefix-name> --oidc-config-id <oidc provider id>  --installer-role-arn <Installer-Role arn>  --hosted-cp --mode auto -y
```

After that, you need to add a Secret `plnsvc-ci-secret` for storing the following items in vault server.

```
PLNSVC_ROSA_TOKEN=<your-rosa-token>
PLNSVC_AWS_KEY_ID=<aws_access_key_id>
PLNSVC_AWS_KEY=<aws_secret_access_key>
```

### Provisioning ROSA HCP Cluster
When the above prerequisites are ready, you can maually execute the following command to provisioning clusters, they will share the same resources created in the above steps.

```
% rosa create cluster --cluster-name <cluster name> --sts --mode=auto --oidc-config-id <oidc provider id> --operator-roles-prefix <prefix-name> --region us-east-1 --version <ocp version , eg: 4.12.16> --compute-machine-type m5.xlarge --subnet-ids=<subnet ids, eg: subnet-001487732ebdd14f4,subnet-0718fb663f4b97f38,subnet-0fe426997da62662c> --hosted-cp -y
```

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
