# Pipeline Services on managed KCP

## Clusters access
Create a directory with the following files:
* `argocd.yaml`: kubeconfig with the active context connecting to the argocd instance;
* `kcp.yaml`: kubeconfig with the active context connecting to your KCP workspace;
* `plnsvc.yaml`: the kubeconfig with with the active context connecting to the Pipeline
  Service cluster.

This directory will be referenced as `KUBECONFIG_DIR`.

The first time one of the deploy/test/reset script is run, use `-k $KUBECONFIG_DIR`.
This will create a local copy of those files in `kcp/work/kubeconfig`. Those files will
then be used by default for every command, until you overwrite their value by specifying
a new `-k $KUBECONFIG_DIR` parameter.

## Clusters configuration
The `deploy.sh -e staging` script will configure the various systems in the staging
environment.

The `test.sh -e staging` script will run a quick pipeline/trigger test on the staging
environment. The expected output looks like this:

```
  - Resources in kcp
NAME                                   READY   STATUS      RESTARTS   AGE
pod/custom-env-gxrkk-pod               0/1     Completed   0          96s
pod/github-run-4stzs-pod               0/1     Completed   0          30s
pod/test-pipelinerun-52gkh-task1-pod   0/3     Completed   0          95s

NAME                                              SUCCEEDED   REASON      STARTTIME   COMPLETIONTIME
taskrun.tekton.dev/custom-env-gxrkk               True        Succeeded   96s         53s
taskrun.tekton.dev/github-run-4stzs               True        Succeeded   30s         20s
taskrun.tekton.dev/test-pipelinerun-52gkh-task1   True        Succeeded   95s         52s

NAME                                            SUCCEEDED   REASON      STARTTIME   COMPLETIONTIME
pipelinerun.tekton.dev/test-pipelinerun-52gkh   True        Succeeded   96s         53s

  - Resources in the plnsvc in namespace kcp5077631d6313cdbfcd21a3fc7343e2a26ba680aefc11f2a4cb656807
NAME                                 READY   STATUS      RESTARTS   AGE
custom-env-gxrkk-pod                 0/1     Completed   0          97s
el-github-listener-f55b777c5-b8gdb   1/1     Running     0          63s
github-run-4stzs-pod                 0/1     Completed   0          31s
test-pipelinerun-52gkh-task1-pod     0/3     Completed   0          96s
```

### Script summary
1. Connect the plnsvc cluster and KCP to ArgoCD.
2. Deploy the various gitops applications to the appropriate clusters.

### Pre-requisites
1. You need to be able to log into the clusters (see the `Cluster access` section).
2. You need to install [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)
3. You need to install [argocd](https://argo-cd.readthedocs.io/en/stable/cli_installation/).
4. You need to install [yq](http://mikefarah.github.io/yq/#install)
