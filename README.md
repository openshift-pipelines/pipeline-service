Test CI

# Pipeline Service

Pipeline Service provides a SaaS for pipelines. It leverages:

- Kubernetes / OpenShift for the compute
- Tekton Pipelines, Results and friends for the core of the service
- OpenShift GitOps / Argo CD, Pipelines as Code for managing the infrastructure


Tekton and Kubernetes provide a great infrastructure for building pipelines. They come however with some limitations.

- Multi-tenancy: Kubernetes provides a level of multi-tenancy. However, this does not extend to cluster scoped resources. CustomResourceDefinitions (CRD) are extensively used for extending the Kubernetes API, following [the operator pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/).  CRDs are cluster scoped. This induces a coupling between the operator version provided by the platform and what you can use as a tenant. The control plane is also shared between tenants.
- Scalability: Kubernetes has made it easy to distribute the load onto many servers and scalability at cloud scale more approachable. Like everything, its control plane has however its limits.
- Availability and geo-redundancy: Kubernetes control plane is based on an etcd cluster, which is sensible to latency between its members. This restricts what can be done in terms of geographical distribution.

Work is in progress in order to solve these challenges.   
**KCP related work was discontinued and can be found in [kcp](https://github.com/openshift-pipelines/pipeline-service/tree/kcp) branch**

## How do I start?

### Running in Kubernetes or OpenShift

You can deploy Pipeline Service on your OpenShift cluster with the [dev_setup.sh](./developer/openshift/dev_setup.sh) script in developer folder.

More info [here](./developer/openshift/README.md).

## Running locally

See [the development guide](./developer/docs/DEVELOPMENT.md) for instructions on how to set up a local development environment.
