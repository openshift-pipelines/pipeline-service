# KCP in Openshift

## and we call it _ckcp_ : containerized-kcp

### Description

This script essentially does this :

1. Install OpenShift GitOps, cert-manager operators on an OpenShift cluster.
2. Run kcp in a container on the Openshift cluster.
3. Set up kcp and compute access by calling relevant scripts (scripts that generate credentials for the OpenShift cluster and kcp workspace so that they could be managed)
4. Install OpenShift Pipelines and/or Triggers on the OpenShift cluster (optional).
5. Register the OpenShift cluster to a kcp workspace (and verify that all resources are synced).

### Dependencies

Before installing the prerequisites, refer [DEPENDENCIES.md](../../DEPENDENCIES.md) to verify the versions of products, operators and tools used in Pipeline Service.

### Pre-requisites

Before you execute the script, you need:

1. to have a _kubernetes/openshift_ cluster with at least 6 CPU cores and 16GB RAM.
2. to install [oc](https://docs.openshift.com/container-platform/4.11/cli_reference/openshift_cli/getting-started-cli.html)
3. to install [argocd CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/)
4. to install [yq](https://mikefarah.gitbook.io/yq/#install)
6. to install [kubectl kcp plugin](https://github.com/kcp-dev/kcp/blob/main/docs/kubectl-kcp-plugin.md)
   Note: ckcp uses the official kcp image in order to run kcp in a pod (latest released versions). It is advisable to use the same version for the kcp plugin as the kcp core API (especially as KCP API is evolving quickly). The current version can be found in [DEPENDENCIES.md](../../DEPENDENCIES.md). Make sure to checkout the branch listed in the doc before installing the plugin.
7. to install [podman](https://github.com/containers/podman) or [docker](https://www.docker.com/). If you have both you can control which is used by setting the `CONTAINER_ENGINE` environment variable (e.g. `export CONTAINER_ENGINE="podman"`). While we do not recommend it for security reasons, you can prefix the binary with `sudo` to force the execution as the root user (e.g. `export CONTAINER_ENGINE="sudo podman"`).

You can run the openshift_dev_setup.sh script with or without parameters as specified below:

```bash
./openshift_dev_setup.sh
    # install openshift-gitops in a host cluster, run kcp in a pod (a.k.a ckcp)
    # setup the host cluster and register it to kcp
```

The test.sh script runs certain examples from tektoncd repo for pipelines and triggers. You can run the below script only after openshift_dev_setup.sh is run and the required resources are up and running.

```bash
./test.sh pipelines
    #Runs PipelineRun which sets and uses some env variables respectively.
    #https://github.com/tektoncd/pipeline/blob/main/examples/v1beta1/pipelineruns/using_context_variables.yaml

./test.sh triggers
    #Simulates a webhook for a Github PR which triggers a TaskRun
    #https://github.com/tektoncd/triggers/tree/main/examples/v1beta1/github

./test.sh pipelines triggers
    #Runs both tests
```

Once the script is done executing, notice that the 8 CRDs (marked in bold below) we specified in [config.yaml](./config.yaml) are synced after we registered our physical cluster with kcp.

<pre>
KUBECONFIG=work/kubeconfig/admin.kubeconfig kubectl api-resources

NAME                              SHORTNAMES   APIVERSION                             NAMESPACED   KIND
configmaps                        cm           v1                                     true         ConfigMap
events                            ev           v1                                     true         Event
limitranges                       limits       v1                                     true         LimitRange
namespaces                        ns           v1                                     false        Namespace
resourcequotas                    quota        v1                                     true         ResourceQuota
secrets                                        v1                                     true         Secret
serviceaccounts                   sa           v1                                     true         ServiceAccount
<br>services                          svc          v1                                     true         Service</br>
mutatingwebhookconfigurations                  admissionregistration.k8s.io/v1        false        MutatingWebhookConfiguration
validatingwebhookconfigurations                admissionregistration.k8s.io/v1        false        ValidatingWebhookConfiguration
customresourcedefinitions         crd,crds     apiextensions.k8s.io/v1                false        CustomResourceDefinition
apiresourceimports                             apiresource.kcp.dev/v1alpha1           false        APIResourceImport
negotiatedapiresources                         apiresource.kcp.dev/v1alpha1           false        NegotiatedAPIResource
apibindings                                    apis.kcp.dev/v1alpha1                  false        APIBinding
apiexports                                     apis.kcp.dev/v1alpha1                  false        APIExport
apiresourceschemas                             apis.kcp.dev/v1alpha1                  false        APIResourceSchema
<br>deployments                       deploy       apps/v1                                true         Deployment</br>
tokenreviews                                   authentication.k8s.io/v1               false        TokenReview
localsubjectaccessreviews                      authorization.k8s.io/v1                true         LocalSubjectAccessReview
selfsubjectaccessreviews                       authorization.k8s.io/v1                false        SelfSubjectAccessReview
selfsubjectrulesreviews                        authorization.k8s.io/v1                false        SelfSubjectRulesReview
subjectaccessreviews                           authorization.k8s.io/v1                false        SubjectAccessReview
certificatesigningrequests        csr          certificates.k8s.io/v1                 false        CertificateSigningRequest
leases                                         coordination.k8s.io/v1                 true         Lease
events                            ev           events.k8s.io/v1                       true         Event
flowschemas                                    flowcontrol.apiserver.k8s.io/v1beta1   false        FlowSchema
prioritylevelconfigurations                    flowcontrol.apiserver.k8s.io/v1beta1   false        PriorityLevelConfiguration
<br>ingresses                         ing          networking.k8s.io/v1                   true         Ingress </br>
<br>networkpolicies                   netpol       networking.k8s.io/v1                   true         NetworkPolicy</br>
clusterrolebindings                            rbac.authorization.k8s.io/v1           false        ClusterRoleBinding
clusterroles                                   rbac.authorization.k8s.io/v1           false        ClusterRole
rolebindings                                   rbac.authorization.k8s.io/v1           true         RoleBinding
roles                                          rbac.authorization.k8s.io/v1           true         Role
locations                                      scheduling.kcp.dev/v1alpha1            false        Location
placements                                     scheduling.kcp.dev/v1alpha1            false        Placement
<br>pipelineruns                      pr,prs       tekton.dev/v1beta1                     true         PipelineRun</br>
<br>pipelines                                      tekton.dev/v1beta1                     true         Pipeline</br>
<br>runs                                           tekton.dev/v1alpha1                    true         Run</br>
<br>tasks                                          tekton.dev/v1beta1                     true         Task</br>
clusterworkspaces                              tenancy.kcp.dev/v1alpha1               false        ClusterWorkspace
clusterworkspacetypes                          tenancy.kcp.dev/v1alpha1               false        ClusterWorkspaceType
workspaces                                     tenancy.kcp.dev/v1beta1                false        Workspace
synctargets                                    workload.kcp.dev/v1alpha1              false        SyncTarget

</pre>

### Development - Onboarding a new component

`ckcp` can be used to develop/test a new component on the Pipeline Service by changing parameters in [config.yaml](./config.yaml).
Considerations for testing a new component:-
1. We are deploying various applications using the GitOps approach and hence a user would need to change the values of `git_url` and `git_ref` to reflect their own Git repo.
2. A user can modify the applications to be deployed on the compute by modifying [apps](./config.yaml).
3. A user can modify the Custom Resources to be synced by the KCP Syncer by modifying [cr_to_sync](./config.yaml).
4. Onboarding a new component requires creating a new Argo CD application in [argo-apps](../../operator/gitops/argocd/argo-apps/) and adding it to [kustomization.yaml](../../operator/gitops/argocd/argo-apps/kustomization.yaml).
5. For testing, users need to modify only the git source path and ref of their Argo CD application to reflect their own Git repo.
6. A user can also choose a different version of kcp than the one running by default by changing the value of [kcp.version](./config.yaml).

### Reset ckcp

One can reset `ckcp` and all the resources deployed by it using:-
```bash
developer/ckcp/hack/util/reset_ckcp.sh --work-dir /path/to/my_dir
```
