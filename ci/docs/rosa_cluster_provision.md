# Red Hat OpenShift Service on AWS (ROSA) Cluster Provisioning

`rosa` is a command line tool that simplifies the use of Red Hat OpenShift Service on AWS, also known as ROSA.
Visit the official ROSA [documentation](https://access.redhat.com/products/red-hat-openshift-service-aws)

We create a ROSA cluster on AWS which manages the HyperShift operator for Pipeline Service.

## How to provision a cluster?

### Pre-requisites:

- AWS account secret access key and access id.
- ROSA Token available [here](https://console.redhat.com/openshift/token/rosa)

### Configure Cluster:

You can configure a ROSA cluster using [rosa_cluster_provision.sh](../hack/rosa_cluster_provision.sh) script.

If successful, you will see a `.json` file with metadata for your cluster!
```json
{
  "CLUSTER_NAME": "your-cluster-name",
  "REGION": "us-west-2",
  "PLATFORM": "rosa",
  "AWS_ACCOUNT_ID": "245687941256",
  "CONSOLE_URL": "<console-url>",
  "API_URL": "<api-url>",
  "USERNAME": "cluster-admin",
  "PASSWORD": "XXXXXXXXXXXX",
  "IDENTITY_PROVIDER": "Cluster-Admin"
}
```