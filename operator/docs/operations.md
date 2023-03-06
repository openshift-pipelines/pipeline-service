
### Introduction
This document provides information on how Pipeline Service is operated and maintained, a SaaS for OpenShift Pipelines. It includes information on the project's working model, deployment modes, testing, security, and upgrade strategy of the operators. The document lists guidelines, which helps ensure a smooth operation of Pipeline Service.

### Project Overview

Pipeline Service is a SaaS (Software as a Service) platform for building and deploying continuous integration and continuous delivery (CI/CD) pipelines. It is designed to work with Kubernetes and OpenShift, and is primarily based on RedHat OpenShift Pipelines under the hood.

More information on Pipeline Service is provided [here](../../README.md).
 
Development Mode: To facilitate the usage of Pipeline Service, developers and SREs can easily try out the software by running it in Development mode on any OpenShift or Kubernetes cluster. Instructions and details on how to use the Development mode are available [here](../../developer).

### Security

Pipeline Service takes security seriously and strives to provide a secure platform. Pipeline Service enforces security measures through a combination of best practices and tooling, which are used to identify and address potential security issues. The team follows established security best practices, including regular updates to dependencies, strong authentication and authorization mechanisms, and secure communication channels. In addition, various tools are used to scan the codebase for potential security vulnerabilities, including [SAST checks](../../.tekton/pipeline-service-static-code-analysis.yaml) and [vulnerability scanning](../../.github/workflows/periodic-scanner-quay.yaml).

#### SAST Checking & Linters

Pipeline Service uses Static Application Security Testing (SAST) to scan the codebase for potential security vulnerabilities. This is done using tools such as SonarQube, and other open-source tools. The SAST scans are run automatically as part of the Continuous Integration (CI) process, and results are reported back to the development team. 

The below tools are currently used in Pipeline Service: 
- [checkov](https://github.com/bridgecrewio/checkov)
- [hadolint](https://github.com/hadolint/hadolint)
- [shellcheck](https://github.com/koalaman/shellcheck)
- [yamllint](https://github.com/adrienverge/yamllint)


#### Vulnerability Scanning

Pipeline Service also employs vulnerability scanning to detect and address potential security issues in its dependencies. This is done using Clair. The vulnerability scans are run regularly, and the results are analyzed by the team to identify any potential risks or issues.

### Tests

Pipeline Service employs a rigorous testing process to ensure the quality and reliability of the service. We run tests on every PR as part of the CI process to catch any issues early in the development cycle. As part of each PR, we run SAST checks to identify potential security vulnerabilities and functional tests to ensure that Pipeline Service remains intact.

We use Tekton Pipelines to run our tests. All our tasks, pipelines, and pipelineruns live in the [.tekton folder](../../.tekton) in our repository. This approach allows us to define the test pipelines in a declarative way, making it easy to maintain and modify. In the future, we plan to dogfood Pipeline Service by using it to test itself. This approach also provides an opportunity to identify any potential issues with the service itself and address them before they affect our users.

### Upgrade Strategy for Operators

Pipeline Service uses Operators, specifically OpenShift Pipelines and OpenShift GitOps, to manage the deployment and configuration of its components and this will continue to be the primary way to handle upgrades. However, some components of Pipeline Service are standalone at the moment and are installed/upgraded using upstream manifests.

We use a GitOps approach in upgrading Pipeline Service. We control the version of the components that are deployed and managed by the OpenShift Pipelines operator by specifying the source and channel in the [Subscription](../../operator/gitops/argocd/pipeline-service/openshift-pipelines/openshift-operator.yaml) of the operator. Using this approach, we can upgrade the components of Pipeline Service in a consistent and reliable way.

We also run a test to ensure that Pipeline Service does not break with the upgrade to the operator version. This [test](../../.tekton/pipeline-service-upgrade-test.yaml) is run as part of our CI process.


