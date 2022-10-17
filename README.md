# Pipeline Service

Pipeline Service provides a SaaS for pipelines. It leverages:

- kcp for serving the API and acting as control plane
- Kubernetes / OpenShift for the compute
- Tekton Pipelines, Results and friends for the core of the service
- OpenShift GitOps / Argo CD, Pipelines as Code for managing the infrastructure


## Why Pipeline Service?

Tekton and Kubernetes provide a great infrastructure for build pipelines. They come however with some limitations.

- Multi-tenancy: Kubernetes provides a level of multi-tenancy. However, this does not extend to cluster scoped resources. CustomResourceDefinitions (CRD) are extensively used for extending the Kubernetes API, following [the operator pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/).  CRDs are cluster scoped. This induces a coupling between the operator version provided by the platform and what you can use as a tenant. The control plane is also shared between tenants.
- Scalability: Kubernetes has made it easy to distribute the load onto many servers and scalability at cloud scale more approachable. Like everything, its control plane has however its limits.
- Availability and geo-redundancy: Kubernetes control plane is based on an etcd cluster, which is sensible to latency between its members. This restricts what can be done in terms of geographical distribution.

kcp helps with mitigating these challenges, pushing the limits to new horizons.

Pipelines as Code is the veneer that brings to the users a great experience directly from their git repository.

**kcp - workspace isolation** (~3 min)
[![asciicast](https://asciinema.org/a/513637.svg)](https://asciinema.org/a/513637)

**kcp - scaling** (~3 min)
[![asciicast](https://asciinema.org/a/516374.svg)](https://asciinema.org/a/516374)

## How do I start?

### Running in Kubernetes or OpenShift

You can deploy this PoC to your Kubernetes cluster with the `openshift_dev_setup.sh` scripts in `ckcp` folder.

More info [here](https://github.com/openshift-pipelines/pipeline-service/tree/main/dev/ckcp)

### Running locally

See [the development documentation](./dev/docs/DEVELOPMENT.md) for instructions on how to set up a local development environment.
