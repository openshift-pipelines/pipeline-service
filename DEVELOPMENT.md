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

[./local/kind/setup.sh](./local/kind/setup.sh) will create two kind clusters and output the kubeconfig files that can be used to interact with the Kubernetes clusters. An amended version of the kubeconfig file with the suffix '_ip' can be used for registering the clusters to Argo CD. A routable IP is used instead of localhost. Simply run:

```console
./local/kind/setup.sh
```

By default, Argo CD is installed on both clusters. It is possible to deactivate its installation by setting an environment variable `NO_ARGOCD=true`

---
**_NOTES:_**

1. Podman is used as the default container engine, if available on the machine. If both podman and docker are available it is possible to force the use of docker by setting an environment variable `CONTAINER_ENGINE=docker`.
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
**_NOTE:_** Podman is used as the default container engine, if available on the machine. If both podman and docker are available it is possible to force the use of docker by setting an environment variable `CONTAINER_ENGINE=docker`.

---

[The kcp registration page](./docs/kcp-registration.md) provides instructions to register workload clusters to kcp.

Here is an example for running the registration image in a development environment:

```bash
podman run --env KCP_ORG='root:pipelines-service' --env KCP_WORKSPACE='compute' --env WORKSPACE_DIR='/workspace' --privileged --volume /home/myusername/plnsvc:/workspace ghcr.io/openshift-pipelines/kcp-registrar:main
```

Make sure that iptables/firewalld is not preventing the communication (tcp initiated from the kind clusters) between the containers running on the kind network and the kcp process on the host.

To check iptables rules:

```bash
sudo iptables -L -n -v
```

The following command can be used to insert a new rule allowing the podman network `10.88.0.1/24` to access the port `6443` of the kcp API server running on a host with IP `192.168.0.121`:

```bash
sudo iptables -I INPUT -p tcp --src 10.88.0.1/24 --dport 6443 --dst 192.168.0.121 -j ACCEPT
```

## Gateway

A gateway can be installed to expose endpoints running on the workload clusters through kcp load balancer. Refer to the [gateway documentation](docs/gateway.md) for the instructions.

## GitOps

Argo CD is by default installed on both clusters. Alternatively, it can be installed afterward by running the following:

```bash
KUBECONFIG=/path-to/config.kubeconfig ./local/argocd/setup.sh
```

Argo CD client can be downloaded from the [Argo CD release page](https://github.com/argoproj/argo-cd/releases/latest).

An ingress is created so that it is possible to login as follows for the first cluster. The port needs to be changed to access the instance on the second cluster:

```bash
argocd login argocd-server-argocd.apps.127.0.0.1.nip.io:8443
```

Argo CD web UI is accessible at <https://argocd-server-argocd.apps.127.0.0.1.nip.io:8443/applications>.

GitOps is the preferred approach for deploying the Pipelines Service. The installed instances of ArgoCD can be leveraged for creating organisations in kcp, universal workspaces used by the infrastructure, installing the Tekton controllers and registering the workload clusters.

The cluster where Argo CD runs is automatically registered to Argo CD.

## Tearing down the environment

As indicated by the kcp start script `ctrl-C` stops all components: kcp, ingress controller and envoy.

The files used by kcp are stored in the directory that was created, whose path was printed out by the script, for example: `/tmp/kcp-pipelines-service.uD5nOWUtU/`
Files in /tmp are usually cleared by a reboot and depending on the operating system may be cleansed when they have not been accessed for 10 days or another elapse of time.

Workload clusters created with kind can be removed with the usual kind command for the purpose `kind delete clusters us-east1 us-west1`
Files for the kind clusters are stored in a directory located in /tmp as well if `$TMPDIR` has not been set to another location.

## Troubleshooting

### Ingress router pods crashloop - "too many open files"

Depending on your machine's configuration, the ingress router and Argo CD pods may crashloop with a "too many open files" error.
This is likely due to the Linux kernel limiting the number of file watches.

On Fedora, this can be fixed by adding a `.conf` file to `/etc/sysctl.d/ increasing the number of file watches and instances:

```bash
# /etc/sysctl.d/98_fs_inotify_increase_watches.conf
fs.inotify.max_user_watches=2097152
fs.inotify.max_user_instances=256
```

### Error: can only create exec sessions on running containers: container state improper

This may happen when the kind containers have stopped because they are ephemeral and do not survive the reboot of the host. This can be fixed by deleting the already created clusters and starting the script again.

```bash
sudo kind delete clusters us-east1 us-west1
```

### Failed to create kind cluster - "Reached target ._Multi-User System._|detected cgroup v1"

This is happening probably due to [Docker Desktop 4.3.0+ using Cgroups v2](https://kind.sigs.k8s.io/docs/user/known-issues/#failure-to-create-cluster-with-docker-desktop-as-container-runtime).

To fix this issue, please ensure that the `KIND_EXPERIMENTAL_PROVIDER=podman` is set properly. You should be able to see _enabling experimental podman provider_ while running kind commands or the scripts. If the issue remains even after this, please try to disable docker and try again.

A final fix is to uninstall docker and use podman only.

### Looping with "error: availableReplicas is not found"

This is _not an issue_, a few lines like this are expected as the script checks for the ingress controller to be ready before creating the ingress object for it. You can wait for a few minutes or if you don't need Argo CD you can pass `NO_ARGOCD=true` before running the script.

If it is too long and the ingress controller is still not ready, that is probably due to the scarcity of file monitors on the system. In that case, increasing `fs`.inotify.max_user_instances` may help. This can be done either by the solution described [above](#ingress-router-pods-crashloop---too-many-open-files) or by running the following command.

```bash
sudo sysctl -w fs.inotify.max_user_instances=256
```

If you are using `podman` the issue could be that the `pids_limit` default value of `2048` is too low. Edit `/usr/share/containers/containers.conf` and increase it (e.g. to `4098`). You could disable the limit entirely with `-1`, but it's not recommended as your system would not be protected against fork bombs anymore.

### "Kind could not be found" when running with sudo

This issue may occur if kind was installed using `go install`. This way kind executable is placed in `GOBIN` (in the home directory) and thus not available to root.

Install kind to any of the root enabled paths i.e `/usr/local/bin` or create a symlink in `/usr/local/bin` pointing to your kind installation. It can be done using the following command.

```bash
sudo ln -s $(which kind) /usr/local/bin/kind
```

### If we install yq via snap store on Fedora, it uses strict confinement policy which does not provide access to root (including /tmp).

```
$ yq e ".current-context" "/tmp/tmp.QNwtlzJzZh/credentials/kubeconfig/compute/compute.kubeconfig.base"
Error: open /tmp/tmp.QNwtlzJzZh/credentials/kubeconfig/compute/compute.kubeconfig.base: no such file or directory
```

Make sure tools such as yq, jq or any other that is using a strict confinement policy is setup to have access to root filesystem. This could be done by installing these tools locally rather than through package managers.