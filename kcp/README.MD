# Pipeline Services on managed KCP

### Pre-requisites
1. You need to be able to log into the clusters (see the `Cluster access` section).
2. You need to install [oc](https://docs.openshift.com/container-platform/4.10/cli_reference/openshift_cli/getting-started-cli.html)
3. You need to install [argocd](https://argo-cd.readthedocs.io/en/stable/cli_installation/).
4. You need to install [yq](http://mikefarah.github.io/yq/#install)
5. Gitlab Infrastructure repo - `git clone git@gitlab.cee.redhat.com:plnsvc/infra.git`.

### Script summary
1. Log into the KCP workspace, the plnsvc cluster and ArgoCD.
2. Connect the plnsvc cluster and KCP to ArgoCD.
3. Deploy the various gitops applications to the appropriate clusters.

## Clusters access
The `./infra/login.sh -e staging` script will log you in into the various systems:
1. KCP
2. KCP workspace
3. pipeline cluster
4. ArgoCD

The script will create various config files in `kcp/work`.

Some tokens have a limited lifetime. If you haven't login for a while, you might start
seeing errors related to authentication/permissions. Running the script again will
refresh the required credentials.

See `./infra/login.sh --help` for available options.

### ArgoCD
No setup is required.

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
