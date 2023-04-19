# Setting up a development environment

For setting up a development environment you will need admin access on a kubernetes cluster.

We have therefore two scripts to get them running on your local machine with minimal resource consumption.

Prerequisites:

- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)
- [kind](https://github.com/kubernetes-sigs/kind)
- a container engine: [podman](https://podman.io/) or [docker](https://docs.docker.com/engine/)
- [git](https://git-scm.com/)
- [jq](https://stedolan.github.io/jq/)

## kubernetes clusters with kind

[developer/local/kind/setup.sh](../local/kind/setup.sh) will create two kind clusters and output the kubeconfig files that can be used to interact with the Kubernetes clusters. An amended version of the kubeconfig file with the suffix '_ip' can be used for registering the clusters to Argo CD. A routable IP is used instead of localhost. Simply run:

```console
developer/local/kind/setup.sh
```

By default, Argo CD is installed on both clusters. It is possible to deactivate its installation by setting an environment variable `NO_ARGOCD=true`

---
**_NOTES:_**

1. Podman is used as the default container engine, if available on the machine. If both podman and docker are available it is possible to force the use of docker by setting an environment variable `CONTAINER_ENGINE=docker`.
2. Podman defaults to running as rootless (see the [kind documentation](https://kind.sigs.k8s.io/docs/user/rootless/) for the prerequisites). To run podman as `root`, prefix `CONTAINER_ENGINE` with `sudo` (e.g. `CONTAINER_ENGINE="sudo docker"`).

---

## GitOps

Argo CD is by default installed on both clusters. Alternatively, it can be installed afterward by running the following:

```bash
KUBECONFIG=/path-to/config.kubeconfig developer/local/argocd/setup.sh
```

Argo CD client can be downloaded from the [Argo CD release page](https://github.com/argoproj/argo-cd/releases/latest).

An ingress is created so that it is possible to login as follows for the first cluster. The port needs to be changed to access the instance on the second cluster:

```bash
argocd login argocd-server-argocd.apps.127.0.0.1.nip.io:8443
```

Argo CD web UI is accessible at <https://argocd-server-argocd.apps.127.0.0.1.nip.io:8443/applications>.

GitOps is the preferred approach for deploying the Pipeline Service.

The cluster where Argo CD runs is automatically registered to Argo CD.

## Tearing down the environment

Files in /tmp are usually cleared by a reboot and depending on the operating system may be cleansed when they have not been accessed for 10 days or another elapse of time.

Clusters created with kind can be removed with the usual kind command for the purpose `kind delete clusters us-east1 us-west1`
Files for the kind clusters are stored in a directory located in /tmp as well if `$TMPDIR` has not been set to another location.
