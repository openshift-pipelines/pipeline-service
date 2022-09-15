# Purpose

This directory contains the manifests used to automate the installation of operators and other components leveraged by Pipeline Service on the workload clusters. It provides an opinionated approach to managing their configuration based on GitOps principles.

## Why GitOps?

We want to make the onboarding experience to use Pipeline Service as easy and customizable as possible. With that in mind, Pipeline Service is built around the principles of GitOps. Using kustomize, users will be able to set up, modify and update cluster resources without having to disrupt their existing setup. We provide base kustomization.yaml files to help get started, so that users can then add their customizations in the overlay/kustomization.yaml files.

## Dependencies

Before installing the prerequisites, refer [DEPENDENCIES.md](../DEPENDENCIES.md) to verify the versions of products, operators and tools used in Pipeline Service.

## Prerequisites

- OpenShift cluster
- OpenShift Pipelines Operator installed (instructions [here](https://docs.openshift.com/container-platform/4.11/cicd/pipelines/installing-pipelines.html))
  Note: To be installed *only* for the first cluster
- OpenShift GitOps operator installed (instructions [here](https://docs.openshift.com/container-platform/4.11/cicd/gitops/installing-openshift-gitops.html))
- Pipelines as Code installed and set up to talk to this repo  (instructions [here](./pac/README.md) and [here](https://pipelinesascode.com/docs/install/installation/))

## Components

Following the Phase 1 architecture described [here](../docs/images/phase1.png), we structured GitOps to set up an OpenShift cluster, i.e.,

- Install various dependencies on the physical cluster via GitOps Applications.
  - tekton pipelines and triggers
  - tekton chains (with the shared `signing-secrets` secret stored in `credentials/manifests/compute/tekton-chains`)
- Log into kcp, and register the clusters using the credentials for accessing kcp shared instance.

Post this, a user will be able to log in to kcp workspace and start creating PipelineRuns :)

## How to run

Currently, we support two ways to get the cluster set up and ready to start creating PipelineRuns. The process to set up the cluster involves the following steps:

1. Prepare repository
2. Generate kubeconfigs 
3. <br />
   Option 1 : Run manual scripts <br />
   Option 2 : Pipelines as Code (PaC) <br />
   &nbsp;&nbsp; a. Install and setup Pipelines As Code <br />
   &nbsp;&nbsp; b. Create and merge a PR


### Prepare repository

Create a new Git repo that would have the following structure. You can also use our [sre folder](./sre) or one of the folders from our [examples](../docs/sre/examples).

```
- .tekton
  - kcp-registration.yaml
  - cluster-setup.yaml
- credentials
  - kubeconfig
    - compute
    - kcp
- environment
  - compute
  - kcp
```

### Generate kubeconfigs

In order to generate the kubeconfig for the cluster and kcp instance with the appropriate permissions using service accounts, we have created a few scripts which are available [here](../images/access-setup/content/bin). 
The [README.md](../images/access-setup/README.md) describes the steps but essentially, you need the below two commands to generate kubeconfig for your cluster and kcp instance respectively. Please refer to the Readme for more details.

```
- ./setup_compute.sh --kubeconfig /home/.kube/mycluster.kubeconfig --work-dir /repo/sre
- ./setup_kcp.sh --kubeconfig /kcp/kcpinstance.kubeconfig --kcp_workspace plnsvc-ws --work-dir /repo/sre
```

### Run manual scripts

One way you could complete the set up process is to run the below scripts manually.  
_Note: Please run these scripts only if you intend not to use PaC to automate the workflow._

    a. To install Tekton components

    ```
    $ WORKSPACE_DIR=/home/workspace/pipeline-service/gitops/sre ../images/cluster-setup/install.sh
    ```

    b. To register the compute clusters into kcp

    ```
    $ KCP_ORG="root:pipeline-service" KCP_WORKSPACE="compute" WORKSPACE_DIR="/home/workspace/pipeline-service/gitops/sre" ../images/kcp-registrar/register.sh
    ```

### Pipelines As Code (PaC)

#### Install and setup Pipelines As Code

The second method which we support is to automate the process by using Pipelines as Code.

Note:
  - Pipelines as Code that needs to be installed and set up does not necessarily have to be on the workload cluster being used for Pipeline Service. It could be on any cluster as long as we have the URL set up and available.
  - If you already have an existing Pipelines as Code setup, then you could skip this step and just make sure that PaC is able to talk to the repo created in step 1. 

There are a couple of steps that need to be done to use PAC in Pipeline Service.
a. Install Pipelines as Code on the OpenShift Cluster.
- Following the instructions from [here](https://pipelinesascode.com/docs/install/installation/) for an OpenShift cluster:
  ```
  kubectl patch tektonconfig config --type="merge" -p '{"spec": {"addon":{"enablePipelinesAsCode": false}}}'
  kubectl apply -f https://raw.githubusercontent.com/openshift-pipelines/pipelines-as-code/stable/release.yaml
  ```
b. In order to set up PaC to listen to PRs, you must push the repository created in step 1 to a Git provider of your choice.

c. From the path of your repo in your system, set up a Git application on any of the Git providers (GitHub, GitLab, Bitbucket etc.) by following the steps from [here](https://pipelinesascode.com).
- As an example, if you wish to set up a GitHub app, Pipelines as Code team recommends using the [tkn pac cli tool](https://pipelinesascode.com/docs/guide/cli/) as it is easy to complete the whole process in just a couple of commands.
   ```
   tkn pac bootstrap github-app
      This command will guide you through the process to create a GitHub app. 
   tkn pac create repo
      This command will create a new Pipelines as Code Repository definition, a namespace where the pipelineruns run and configures webhook.
   ```
- Note: 
  - You need to install the GitHub app on your desired repository apart from the above two steps.
  - You need to disable SSL in the GitHub app settings if you are using self-signed certificate.
- PaC also supports the above steps on other Git providers such as Gitlab, Bitbucket all of which is documented [here](https://pipelinesascode.com/).

Once the above two steps are done, the GitHub app (or any other Git provider app) you've set up from step 2 is now talking to PAC and would watch PRs and trigger PipelineRuns that automate the workflow previously described.

#### Create and merge a PR

Now that we have everything ready, we can create a PR on the repo with the following files. 

_Note: mycluster.kubeconfig, mykcp.kubeconfig, mycluster and kustomization.yaml are all generated by setup_compute.sh and setup_kcp.sh scripts. Based on your requirement, you can customize the configuration under kustomization.yaml. Refer [examples](../docs/sre/examples) for more information._

```
- .tekton
    - kcp-registration.yaml
    - cluster-setup.yaml
- credentials
    - kubeconfig
        - compute
          - mycluster.kubeconfig    //kubeconfig of your cluster
        - kcp
          - mykcp.kubeconfig        //kubeconfig of your kcp shared instance
- environment
    - compute
      - mycluster                   //folder with the same name as your cluster
        - kustomization.yaml        //kustomization file which points to Argo CD resources


$cat kustomization.yaml
resources:
  - github.com/openshift-pipelines/pipeline-service/gitops/argocd?ref=main
```

Once you merge the PR, PaC will trigger cluster-setup and kcp-registrar Pipelines present under _.tekton_ to set up the cluster and register it with kcp instance.

## Next steps

Once you have completed the above process, you can start creating PipelineRuns in a user workspace in kcp.
To take advantage of the workload cluster, users should now create an APIBinding in their own workspaces to the APIExport created by kcp upon the addition of a workload cluster (via the sync command). This mechanism of APIExport and APIBindings makes it possible to use the same compute (workload cluster) with multiple workspaces.

Below snippet shows the default APIExport CR named 'kubernetes' created in a workspace named 'compute'. 

```
$ KUBECONFIG=kcpinstance.kubeconfig kubectl ws
Current workspace is "root:${ORG_ID}:compute".

#Below apiexport CR named 'kubernetes' is created automatically once we sync the workload cluster to the workspace 
$ KUBECONFIG=kcpinstance.kubeconfig kubectl get apiexports
NAME         AGE
kubernetes   46h
 
$ KUBECONFIG=kcpinstance.kubeconfig kubectl get apiexports/kubernetes -o yaml _(truncated output shown below)_
apiVersion: apis.kcp.dev/v1alpha1
kind: APIExport
metadata:
  name: kubernetes
spec:
  identity:
    secretRef:
      name: kubernetes
      namespace: kcp-system
  latestResourceSchemas:
  - rev-158351.deployments.apps

```

Users must be authorized to bind APIExports on the workspace hosting the SyncTarget, or they will get an `unable to create APIImport: missing verb='bind' permission on apiexports` error. The default configuration will grant the `bind` permission to all authenticated users (c.f. `gitops/kcp/registration`). This configuration can be customized by creating the appropriate manifest(s) in the `environment/kcp` folder (c.f. [this example](../docs/sre/examples/providers/environment/kcp/kustomization.yaml)).

Below snippet shows the APIBinding used in a new workspace named 'user'.

```
$ KUBECONFIG=kcpinstance.kubeconfig kubectl ws use user
Current workspace is "root:${ORG_ID}:user" (type "Universal").

echo "apiVersion: apis.kcp.dev/v1alpha1
kind: APIBinding
metadata:
  name: cluster-workspace
spec:
  reference:
    workspace:
      path: root:${ORG_ID}:compute
      exportName: kubernetes" | kubectl create -f -

 
$ KUBECONFIG=kcpinstance.kubeconfig kubectl get apibinding
NAME                AGE
cluster-workspace   45h
 
$ KUBECONFIG=kcpinstance.kubeconfig kubectl get apibinding/cluster-workspace -o yaml _(truncated output shown below)_
apiVersion: apis.kcp.dev/v1alpha1
kind: APIBinding
metadata:
  name: cluster-workspace
spec:
  reference:
    workspace:
      exportName: kubernetes
      path: root:${ORG_ID}:compute

```
