# Phase 2

In the second phase, the controllers used by Pipeline Service are made kcp-aware. This eliminates the need to sync the pipeline resources onto workload clusters and to have operators directly bound to any kubernetes cluster.
This brings additional benefits:

- not being tied up to a version of pipeline CRDs installed on a Kubernetes cluster
- being able to scale controllers and distribute their load independently from the Kubernetes clusters
- flexibility in setting up failure domains

Tekton resource schemas are added only in kcp.

Kubernetes workload clusters know nothing about Tekton. They only run resources like Deployments, Pods and Services.

![Phase 2 flow](./docs/images/phase2.png)
