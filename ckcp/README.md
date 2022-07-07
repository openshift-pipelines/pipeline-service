# KCP in Openshift

## and we call it _ckcp_ : containerized-kcp

### Description

This script essentially does this :  

Short Version:

1. Run kcp in a container in an Openshift cluster.
2. Add the current cluster as a physical cluster when running KCP in k8s.
3. Install pipelines and/or triggers (optional)

Long Version:

1. Create ns, sa, and add appropriate scc.
2. Create deployment and service resources.
3. Copy kubeconfig from inside the pod to the local system.
4. Update route of kcp-service in the just copied admin.kubeconfig file.
5. Copy a physical cluster's kubeconfig inside a pod.
6. Add a physical cluster to kcp running inside the pod.  
   **_(optional)_**
7. Apply patches to the pipelines repo and run the controller.
8. Run some examples PipelineRuns.
9. Apply patches to the triggers repo and run the controller, interceptor and eventlistener.

### Pre-requisites

Before you execute the script,

1. You need to have a _kubernetes/openshift_ cluster.
2. You need to install [oc](https://docs.openshift.com/container-platform/4.9/cli_reference/openshift_cli/getting-started-cli.html)
3. You need to install [argocd](https://argo-cd.readthedocs.io/en/stable/cli_installation/).
4. You need to install [yq](https://mikefarah.gitbook.io/yq/#install)
6. You need to install [kubectl kcp plugin](https://github.com/kcp-dev/kcp/blob/main/docs/kubectl-kcp-plugin.md)
   Note: ckcp uses the official kcp image in order to run kcp in a pod (latest released versions). It is advisable to use the same version for the kcp plugin as the kcp core API (especially as KCP API is evolving quickly). The current version can be found in this [file](./openshift/overlays/dev/kustomization.yaml) as the 'newTag' variable. Make sure to checkout this branch before installing the plugin.

You can run the openshift_dev_setup.sh script with or without parameters as specified below:  
Note: Triggers require pipelines to be running and thus running ckcp with triggers alone is not supported.

```bash
./openshift_dev_setup.sh
    #installs openshift-gitops in a host cluster, install kcp in a pod (a.k.a ckcp)
    #and register the kcp cluster to the ArgoCD instance

./openshift_dev_setup.sh -a pipelines
    #installs openshift-gitops + ckcp + openshift-pipeline
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

Once the script is done executing, notice that the 7 CRDs(marked in bold as below) we specified when we started kcp are synced after we registered our physical cluster with kcp.

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
mutatingwebhookconfigurations                  admissionregistration.k8s.io/v1        false        MutatingWebhookConfiguration
validatingwebhookconfigurations                admissionregistration.k8s.io/v1        false        ValidatingWebhookConfiguration
customresourcedefinitions         crd,crds     apiextensions.k8s.io/v1                false        CustomResourceDefinition
apiresourceimports                             apiresource.kcp.dev/v1alpha1           false        APIResourceImport
negotiatedapiresources                         apiresource.kcp.dev/v1alpha1           false        NegotiatedAPIResource
apibindings                                    apis.kcp.dev/v1alpha1                  false        APIBinding
apiexports                                     apis.kcp.dev/v1alpha1                  false        APIExport
apiresourceschemas                             apis.kcp.dev/v1alpha1                  false        APIResourceSchema
deployments                       deploy       apps/v1                                true         Deployment
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
<b>repositories                      repo         pipelinesascode.tekton.dev/v1alpha1    true         Repository</b>
clusterrolebindings                            rbac.authorization.k8s.io/v1           false        ClusterRoleBinding
clusterroles                                   rbac.authorization.k8s.io/v1           false        ClusterRole
rolebindings                                   rbac.authorization.k8s.io/v1           true         RoleBinding
roles                                          rbac.authorization.k8s.io/v1           true         Role
locations                                      scheduling.kcp.dev/v1alpha1            false        Location
<b>conditions                                     tekton.dev/v1alpha1                    true         Condition
pipelineresources                              tekton.dev/v1alpha1                    true         PipelineResource
pipelineruns                      pr,prs       tekton.dev/v1beta1                     true         PipelineRun
pipelines                                      tekton.dev/v1beta1                     true         Pipeline
runs                                           tekton.dev/v1alpha1                    true         Run
tasks                                          tekton.dev/v1beta1                     true         Task</b>
workloadclusters                               workload.kcp.dev/v1alpha1              false        WorkloadCluster
</pre>

### How to get access on an already setup cluster

Configure kubectl to point to your physical cluster and run:

```bash
kubectl get secret kcp-kubeconfig -n ckcp  -o jsonpath="{.data['admin\.kubeconfig']}" > kubeconfig
```
