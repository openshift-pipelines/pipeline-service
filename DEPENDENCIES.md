
*This document lists all the various products/tools used in Pipeline Service along with their current versions. We also use this document to track the evolution of the products/tools as and when they are upgraded.*


### **Products**

| **Component**                 | **Version**                                                                                                                           | **Purpose**                                                                  | **Comments**                                                                                                                                                               |
|-------------------------------|---------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| OpenShift                     | 4.11                                                                                                                                  | Platform                                                                     | Upgrades to next versions 4.11 need to be tested and approved |
| ovn-kubernetes Network Plugin | 0.3.0                                                                                                                                 | Prerequisite for enabling certain Network Policies                           | During the cluster creation, one needs to choose ovn-kubernetes as the network plugin (as opposed to OpenShift SDN) |
| Tekton Pipelines              | 0.37.4                                                                                                                                | Core component of Pipeline Service providing pipelines resources             | Controlled by OpenShift Pipelines Operator |
| Tekton Triggers               | 0.20.2                                                                                                                                | Event Based Triggers for Tekton Pipelines                                    | Controlled by OpenShift Pipelines Operator |
| Pipelines as Code             | 0.15.0                                                                                                                                | A user facing CI to interfact with Pipeline Service                          | Installed directly from upstream |
| Tekton Results                | 0.4.0                                                                                                                                 | Result storage for Pipeline Service                                          | Modified version of Results installed and maintained by Pipeline Service |
| Tekton Chains                 | 0.13.0                                                                                                                                | Artifact signatures and attestations                                         | Modified version of Chains installed and maintained by Pipeline Service team |
| kind                          | see [dependencies.sh](shared/config/dependencies.sh)                                                                                  | For local development only                                                   | Spawns a Kubernetes-in-Docker clusters. No requirement to use a particular version. Users can install the latest version available at the time |
| OpenShift GitOps              | 1.6.0                                                                                                                                 | Prerequisite for managing the installation and lifecycle of components       | OpenShift GitOps uses Argo CD (2.4.5) as the declarative GitOps engine |
| Postgres                      | 2.3.5                                                                                                                                 | Installed and setup as part of Tekton Results installation                   | For development purposes (store tekton results). No requirement to use a particular version; users can install the latest version available at the time |
| Amazon RDS                    | N/A                                                                                                                                   | External DB for Tekton Results                                               | For storing tekton results in an external database. No requirement to use a particular version. A specific configuration is required for connection and security purposes |


### **Operators**

| **Component**                | **Version**                            | **Purpose** | **Comments** |
|------------------------------|----------------------------------------|-------------|--------------|
| OpenShift Pipelines Operator | openshift-pipelines-operator-rh.v1.8.0 |             |              |
| OpenShift GitOps Operator    | openshift-gitops-operator.v1.5.6       |             |              |

### **Tools**

| **Component**      | **Version**                                          | **Purpose**                                                                 | **Comments** |
|--------------------|------------------------------------------------------|-----------------------------------------------------------------------------|--------------|
| oc (OpenShift CLI) | see [dependencies.sh](shared/config/dependencies.sh) | To interact with the cluster                                                | Follows OpenShift version |
| kubectl            | see [dependencies.sh](shared/config/dependencies.sh) | To interact with the cluster                                                | Follows kubernetes version which follows OpenShift version. We only need either oc or kubectl |
| tkn                | see [dependencies.sh](shared/config/dependencies.sh) | To interact with tekton                                                     | |
| tkn pac plugin     | 0.15.0                                               | To set up PaC                                                               | Optional plugin for customers during the cluster setup phase. Follows PaC Version |
| Argo CD (client)   | see [dependencies.sh](shared/config/dependencies.sh) | To run Argo CD related commands                                             | Follows version of argocd engine used in openshift gitops |
| checkov            | see [dependencies.sh](shared/config/dependencies.sh) | Validate k8s manifests                                                      | |
| hadolint           | see [dependencies.sh](shared/config/dependencies.sh) | Validate Dockerfiles                                                        | |
| shellcheck         | see [dependencies.sh](shared/config/dependencies.sh) | Validate shell scripts | |
| skopeo             | 1.y.z                                                | Interact with images                                                        | |
| yamllint           | see [dependencies.sh](shared/config/dependencies.sh) | Validate YAML                                                               | |
| yq                 | see [dependencies.sh](shared/config/dependencies.sh) | Required for parsing things; used in various scripts throughout the project | Certain features are not supported with versions < 4.18.1. Use Latest version to avoid any issues |
| docker             | 20.10.z                                              | For local development only                                                  | Only one of docker or podman is required. No requirement to use a particular version; users can install the latest version available at the time |
| podman             | 4.0.0                                                | For local development only                                                  | Only one of docker or podman is required. No requirement to use a particular version; users can install the latest version available at the time |
| openssl            | 3.0.2                                                | To manipulate certificate information during cluster regsitration           | |
| bitwarden          | see [dependencies.sh](shared/config/dependencies.sh) | To store credentials outside the gitops repository                          | |
| minio              | 4.5.6                                                | S3 compatable storage for tekton-results api server                         | |