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

By default Argo CD is installed on the first cluster. It is possible to deactivate its installation by setting an environment variable `NO_ARGOCD=true`

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

## Gateway

A gateway can be installed to expose endpoints running on the workload clusters through kcp load balancer. Refer to the [gateway documentation](docs/gateway.md) for the instructions.

## GitOps

Argo CD is by default installed on the first cluster. Alternatively it can be installed afterwards by running the following:

```console
KUBECONFIG=/path-to/config.kubeconfig ./local/argocd/setup.sh
```

Argo CD client can be downloaded from the [Argo CD release page](https://github.com/argoproj/argo-cd/releases/latest).

An ingress is created so that it is possible to login as follows:

```console
argocd login argocd-server-argocd.apps.127.0.0.1.nip.io:8443
```

Argo CD web UI is accessible at https://argocd-server-argocd.apps.127.0.0.1.nip.io:8443/applications.

GitOps is the preferred approach for deploying the Pipelines Service. The installed instance of ArgoCD can be leveraged for creating organisations in kcp, universal workspaces used by the infrastructure, installing the Tekton controllers and registering the workload clusters.

[The Argo CD page](./docs/argocd.md) provides instructions to register workload clusters to Argo CD.

In a development environment a few network and name resolution aspects need to be taken into consideration:
- argocd-server-argocd.apps.127.0.0.1.nip.io is resolved to 127.0.0.1, which is not suitable for communication between containers. When running the argocd container for registration `--add-host argocd-server-argocd.apps.127.0.0.1.nip.io:<kind-cluster-ip-address>` can help with name resolution. The IP address of the kind cluster can be retrieved by inspecting the kind container and taking the value of IPAddress for the kind network.
- certificates may not have been signed for the argocd-server-argocd.apps.127.0.0.1.nip.io route. `--env INSECURE='true'` can be used for working around this point.
- make sure that iptables/firewalld are not preventing the communication between the localhost and the containers.

Here is an example for running the registration image in a development environment:
~~~
podman run --add-host argocd-server-argocd.apps.127.0.0.1.nip.io:10.89.0.26 --env INSECURE='true' --env ARGO_URL='argocd-server-argocd.apps.127.0.0.1.nip.io:443' --env ARGO_USER='admin' --env ARGO_PWD='xxxxxxxx' --env DATA_DIR='/workspace' --privileged --volume /home/myusername/plnsvc:/workspace quay.io/myuser/pipelines-argocd
~~~

## Tearing down the environment

As indicated by the kcp start script `ctrl-C` stops all components: kcp, ingress controller and envoy.

The files used by kcp are stored in the directory that was created, whose path was printed out by the script, for example: `/tmp/kcp-pipelines-service.uD5nOWUtU/`
Files in /tmp are usually cleared by reboot and depending on the operating system may be cleansed when they have not been accessed for 10 days or another elapse of time.

Workload clusters created with kind can be removed with the usual kind command for the purpose `kind delete clusters us-east1 us-west1`
Files for the kind clusters are stored in a directory located in /tmp as well if `$TMPDIR` has not been set to another location.

## Troubleshooting

### Ingress router pods crashloop - "too many open files"

Depending on your machine's configuration, the ingress router and ArgoCD pods may crashloop with a "too many open files" error.
This is likely due to the Linux kernel limiting the number of file watches.

On Fedora, this can be fixed by adding a `.conf` file to `/etc/sysctl.d/ increasing the number of file watches and instances:

```sh
# /etc/sysctl.d/98_fs_inotify_increase_watches.conf
fs.inotify.max_user_watches=2097152
fs.inotify.max_user_instances=256
```
