# Pipelines-service

Pipelines-service provides a SaaS for pipelines. It leverages Kubernetes, Tekton, Tekton Triggers, Tekton Results, Pipelines as Code together with kcp.

## Why Pipelines-service?

Tekton and Kubernetes provide a great infrastructure for build pipelines. They come however with some limitations.

- Multi-tenancy: Kubernetes provides a level of multi-tenancy. CustomResourceDefinitions are however cluster scoped. This induces a coupling between the operator version provided by the platform and what you can use as a tenant. The control plane is also shared between tenants.
- Scalability: Kubernetes has made it easy to distribute the load onto many servers and scalability at cloud scale more approachable. Like everything, its control plane has however its limits.
- Availability and geo-redundancy: Kubernetes control plane is based on an etcd cluster, which is sensible to latency between its members. This restricts what can be done in terms of geographical distribution.

kcp helps with mitigating these challenges, pushing the limits to new horizons.

Pipelines as Code is the veneer that brings to the users a great experience directly from their git repository.

## Design

### Phase 1

In the first phase, Pipelines-service will leverage kcp Transparent-Multi-Cluster capabilities. Tekton and other controllers run directly on Kubernetes workload clusters and process the resources there. kcp syncer ensures that resources (Pipelines, PipelineRuns, etc.) created by users in their workspace are synced onto a workload cluster and the result of the processing is reflected to the user workspace.

This approach has the great advantage of not requiring any change to the controllers.

Controllers know nothing about kcp.

![Phase 1 flow](./docs/images/phase1.png)

**[Limitations](./docs/phase1_limitations.md)**

**Demo** (5mns)

[![asciicast](https://asciinema.org/a/duvHbVhNXvX1AeISR2sGBpvAY.svg)](https://asciinema.org/a/duvHbVhNXvX1AeISR2sGBpvAY)

### Phase 2

In the second phase, the controllers used by Pipelines-service are made kcp-aware. This eliminates the need to sync the pipeline resources onto workload clusters and to have operators directly bound to any kubernetes cluster.
This brings additional benefits:

- not being tied up to a version of pipeline CRDs installed on a Kubernetes cluster
- being able to scale controllers and distribute their load independently from the Kubernetes clusters
- flexibility in setting up failure domains

Tekton resource schemas are added only in kcp.

Kubernetes workload clusters know nothing about Tekton. They only run resources like Deployments, Pods and Services.

![Phase 2 flow](./docs/images/phase2.png)

## How do I start?

### Running in Kubernetes or OpenShift

You can deploy this PoC to your Kubernetes cluster with the `build.sh` and `run.sh` scripts in `ckcp` folder.

More info [here](https://github.com/openshift-pipelines/pipelines-service/tree/main/ckcp)

## Running locally

See [the development [guide](DEVELOPMENT.md) for instructions on how to set up a local development environment.
