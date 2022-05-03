# Setting up a development environment

For setting up a development environment you will need two things:

- Kubernetes workload clusters
- A kcp cluster

We have therefore two scripts to get them running on your local machine with minimal resource consumption.

Prerequisites:
- [kind](https://github.com/kubernetes-sigs/kind)
- a container engine: [podman](https://podman.io/) or [docker](https://docs.docker.com/engine/)
- [git](https://git-scm.com/)

## Workload clusters with kind

[./local/kind/setup.sh](./local/kind/setup.sh) will create two kind clusters and the files to register them so that it is straightforward to add them to the kcp cluster. Kind will also output the kubeconfig files that can be used to interact with the Kubernetes clusters. Simply run:

```console
./local/kind/setup.sh
```

---
**_NOTES:_**

1. Podman is used per default as container engine if available on the machine. If both podman and docker are available it is possible to force the use of docker by setting an environment variable `CONTAINER_ENGINE=docker`.
2. Podman defaults to running as sudo (root). To run podman in rootless mode, use the environment variable `ALLOW_ROOTLESS=true`. See the [kind documentation](https://kind.sigs.k8s.io/docs/user/rootless/) for the prerequisites.
 
---

## kcp cluster

[./local/kcp/start.sh](./local/kcp/start.sh) will set up a kcp cluster with ingress controller and envoy.

The script can be customized by setting the following optional environment variables:

| Name | Description |
|------|-------------|
| KCP_DIR | a directory with kcp source code, default to a git clone of kcp in the system temp directory |
| KCP_BRANCH | the branch to use. Mind that the script will do a git checkout, to a default release if the branch is not specified |
| PARAMS | the parameters to start kcp with |

The script will output the location of the kubeconfig file that can be used to interact with the kcp API.

```console
./local/kcp/start.sh
```

---
**_NOTE:_**  podman is used per default as container engine if available on the machine. If both podman and docker are available it is possible to force the use of docker by setting an environment variable `CONTAINER_ENGINE=docker`.

---

The normal procedure can then be followed to create the required organisation, user workspaces, installing the Tekton controllers and registering the workload clusters.

## Gateway

A gateway can be installed to expose endpoints running on the workload clusters through kcp load balancer. Refer to the [gateway documentation](docs/gateway.md) for the instructions.

## Tearing down the environment

As indicated by the kcp start script `ctrl-C` stops all components: kcp, ingress controller and envoy.

The files used by kcp are stored in the directory that was created, whose path was printed out by the script, for example: `/tmp/kcp-pipelines-service.uD5nOWUtU/`
Files in /tmp are usually cleared by reboot and depending on the operating system may be cleansed when they have not been accessed for 10 days or another elapse of time.

Workload clusters created with kind can be removed with the usual kind command for the purpose `kind delete clusters us-east1 us-west1`
Files for the kind clusters are stored in a directory located in /tmp as well if `$TMPDIR` has not been set to another location.
