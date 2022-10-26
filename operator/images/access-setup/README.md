# Access Setup

## Goals
Given a new KCP instance or compute cluster, deploy the minimum
amount of resources required to operate that cluster from a git repository
implementing a CD process (c.f. gitops/sre). The CD process will then be
responsible for installing/registering all the required resources.

This action needs to be performed only once in the lifetime of the resource
being initialized. If the resource creation is automated, the initialization
can be done using the `quay.io/redhat-pipeline-service/access-setup:main` image instead of
checking out the repository and running the script.

## Definitions

* Pipeline Service SRE team: The team responsible for deploying and managing
  Pipeline Service on one or more KCP instances and workspaces. This team may not be in
  charge of managing the kcp cluster (out of scope of this project) but is in charge of
  creating workspaces, the content necessary for running Pipeline Service and
  associated RBAC. The team is also in charge of managing the addition of compute
  clusters to the Pipeline Service platform and of managing the lifecycle of the
  components running on them.

## KCP
`setup_kcp.sh` needs to be run once by the Pipeline Service SRE team for each
`KCP instance`/`KCP organization` pair operated by the Pipeline Service SRE team.

The script will:
1. Create the `$KCP_WORKSPACE` workspace in the organization workspace.
2. Create a `pac-manager` serviceaccount in the new workspace, in the `pipelines-as-code` namespace.
3. Generate the kubeconfig for the serviceaccount.

Example: `./setup_kcp.sh --kubeconfig /home/.kube/mykcp.kubeconfig --kcp-org root:pipeline-service --kcp-workspace compute --work-dir /path/to/sre/repository`

The generated kubeconfig must then be placed in the `credentials/kubeconfig/kcp`
folder of the SRE gitops repository to enable the automation of the compute
registration to kcp.

## Compute
`setup_compute.sh` needs to be run once by the Pipeline Service SRE team for
each compute cluster operated by the Pipeline Service SRE team.

The script will:
1. Create a `pac-manager` serviceaccount in the `pipelines-as-code` namespace.
2. Generate the kubeconfig for the serviceaccount.
3. Create a default `kustomization.yaml` for the cluster under `environment/compute
environment/compute`.
4. Create shared secrets for tekton-chains and tekton-results

Example: `./setup_compute.sh --kubeconfig /home/.kube/mycluster.kubeconfig --work-dir /path/to/sre/repository`

A pull request needs to be submitted on the SRE gitops repository to add:
* the generated kubeconfig to the `credentials/kubeconfig/compute` folder;
* the generated folder holding the `kustomization.yaml` to the `environment/compute` folder.
Merging the pull request will enable the automation of the deployment of the 
Pipeline Service on the cluster and the registration of the cluster to kcp.
