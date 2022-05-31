# Argo CD registration

When using a central instance or service for Argo CD, external clusters need to get registered to it.

The [images/argocd-registrar directory](../images/argocd-registrar) directory contains the logic used for that.

## Run

The registration is meant to be triggered from [Pipelines as Code](https://pipelinesascode.com/) and a [Tekton PipelineRun](../gitops/pac/.tekton/argo-registration.yaml) is provided for the purpose in the .tekton directory.

Alternatively the registration can be performed by manually calling the registration script in the image directory:

```console
ARGO_URL="https://argoserver.com" ARGO_USER="user" ARGO_PWD="xxxxxxxxx" DATA_DIR="/workspace" ./register.sh
```

DATA_DIR should point to a directory with a fork of this repository including
- the kubeconfig files of the clusters to register in `gitops/sre/credentials/kubeconfig/compute`
- two kustomization files for each cluster under two folders:
  - `gitops/sre/environment/compute/$cluster/namespaces/kustomization.yaml` using `gitops/sre/environment/compute/base/namespaces` as base and any desired customization.
  - `gitops/sre/environment/compute/$cluster/argocd-rbac/kustomization.yaml` using `gitops/sre/environment/compute/base/argocd-rbac` as base and any desired customization.

~~~
cat <<EOF > kustomization.yaml
resources:
- ../../base/namespaces
EOF
~~~

~~~
cat <<EOF > kustomization.yaml
resources:
- ../../base/argocd-rbac
EOF
~~~

## Authentication

Tekton PipelineRun relies on a secret named argocd-credentials in the same namespace as the PipelineRun for the authentication against the Argo CD server. This can be created as follows:
~~~
kubectl create secret generic argocd-credentials \
  --from-literal=url='argocd-server.argocd' \
  --from-literal=user='admin' \
  --from-literal=pwd='xxxxxxxxx'
~~~

## Development

In a development environment a few network and name resolution aspects need to be taken into consideration:
- argocd-server-argocd.apps.127.0.0.1.nip.io is resolved to 127.0.0.1, which is not suitable for communication between containers. When running the argocd container for registration `--add-host argocd-server-argocd.apps.127.0.0.1.nip.io:<kind-cluster-ip-address>` can help with name resolution. The IP address of the kind cluster can be retrieved by inspecting the kind container and taking the value of IPAddress for the kind network.
- certificates may not have been signed for the argocd-server-argocd.apps.127.0.0.1.nip.io route. `--env INSECURE='true'` can be used for working around this point.
- make sure that iptables/firewalld are not preventing the communication between the localhost and the containers.

Here is an example for running the registration image in a development environment:
~~~
podman run --add-host argocd-server-argocd.apps.127.0.0.1.nip.io:10.89.0.26 --env INSECURE='true' --env ARGO_URL='argocd-server-argocd.apps.127.0.0.1.nip.io:443' --env ARGO_USER='admin' --env ARGO_PWD='xxxxxxxx' --env DATA_DIR='/workspace' --privileged --volume /home/myusername/plnsvc:/workspace quay.io/myuser/pipelines-argocd
~~~

