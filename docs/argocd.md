# Argo CD registration

The [images/argocd directory](../images/argocd) directory contains the logic used for registering the clusters to Argo CD.

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
