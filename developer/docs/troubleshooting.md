# Troubleshooting

## Ingress router pods crashloop - "too many open files"

Depending on your machine's configuration, the ingress router and Argo CD pods may crashloop with a "too many open files" error.
This is likely due to the Linux kernel limiting the number of file watches.

On Fedora, this can be fixed by adding a `.conf` file to `/etc/sysctl.d/ increasing the number of file watches and instances:

```bash
# /etc/sysctl.d/98_fs_inotify_increase_watches.conf
fs.inotify.max_user_watches=2097152
fs.inotify.max_user_instances=256
```

## Error: can only create exec sessions on running containers: container state improper

This may happen when the kind containers have stopped because they are ephemeral and do not survive the reboot of the host. This can be fixed by deleting the already created clusters and starting the script again.

```bash
sudo kind delete clusters us-east1 us-west1
```

## Failed to create kind cluster - "Reached target ._Multi-User System._|detected cgroup v1"

This is happening probably due to [Docker Desktop 4.3.0+ using Cgroups v2](https://kind.sigs.k8s.io/docs/user/known-issues/#failure-to-create-cluster-with-docker-desktop-as-container-runtime).

To fix this issue, please ensure that the `KIND_EXPERIMENTAL_PROVIDER=podman` is set properly. You should be able to see _enabling experimental podman provider_ while running kind commands or the scripts. If the issue remains even after this, please try to disable docker and try again.

A final fix is to uninstall docker and use podman only.

## Looping with "error: availableReplicas is not found"

This is _not an issue_, a few lines like this are expected as the script checks for the ingress controller to be ready before creating the ingress object for it. You can wait for a few minutes or if you don't need Argo CD you can pass `NO_ARGOCD=true` before running the script.

If it is too long and the ingress controller is still not ready, that is probably due to the scarcity of file monitors on the system. In that case, increasing `fs`.inotify.max_user_instances` may help. This can be done either by the solution described [above](#ingress-router-pods-crashloop---too-many-open-files) or by running the following command.

```bash
sudo sysctl -w fs.inotify.max_user_instances=256
```

If you are using `podman` the issue could be that the `pids_limit` default value of `2048` is too low. Edit `/usr/share/containers/containers.conf` and increase it (e.g. to `4098`). You could disable the limit entirely with `-1`, but it's not recommended as your system would not be protected against fork bombs anymore.

## "Kind could not be found" when running with sudo

This issue may occur if kind was installed using `go install`. This way kind executable is placed in `GOBIN` (in the home directory) and thus not available to root.

Install kind to any of the root enabled paths i.e `/usr/local/bin` or create a symlink in `/usr/local/bin` pointing to your kind installation. It can be done using the following command.

```bash
sudo ln -s $(which kind) /usr/local/bin/kind
```

## If we install yq via snap store on Fedora, it uses strict confinement policy which does not provide access to root (including /tmp).

```
$ yq e ".current-context" "/tmp/tmp.QNwtlzJzZh/credentials/kubeconfig/compute/compute.kubeconfig.base"
Error: open /tmp/tmp.QNwtlzJzZh/credentials/kubeconfig/compute/compute.kubeconfig.base: no such file or directory
```

Make sure tools such as yq, jq or any other that is using a strict confinement policy is setup to have access to root filesystem. This could be done by installing these tools locally rather than through package managers.
