# Access Setup

## Goals
Given a new compute cluster, deploy the minimum
amount of resources required to operate that cluster from a git repository
implementing a CD process (c.f. operator/gitops/sre). The CD process will then be
responsible for installing/registering all the required resources.

This action needs to be performed only once in the lifetime of the resource
being initialized. If the resource creation is automated, the initialization
can be done using the `quay.io/redhat-pipeline-service/access-setup:main` image instead of
checking out the repository and running the script.

## Definitions

* Pipeline Service SRE team: The team responsible for deploying and managing
  Pipeline Service and the life cycle of its components on one or more compute instances.

## Compute
`setup_compute.sh` needs to be run once by the Pipeline Service SRE team for
each compute cluster operated by the Pipeline Service SRE team.

The script will:
1. Create a `pipeline-service-manager` serviceaccount in the `pipeline-service` namespace.
2. Generate the kubeconfig for the serviceaccount.
3. Create a default `kustomization.yaml` for the cluster under `environment/compute
environment/compute`.
4. Create shared secrets for tekton-chains and tekton-results

Example: `./setup_compute.sh --kubeconfig /home/.kube/mycluster.kubeconfig --work-dir /path/to/sre/repository`

A pull request needs to be submitted on the SRE gitops repository to add:
* the generated kubeconfig to the `credentials/kubeconfig/compute` folder;
* the generated folder holding the `kustomization.yaml` to the `environment/compute` folder.
Merging the pull request will enable the automation of the deployment of the 
Pipeline Service on the cluster.
