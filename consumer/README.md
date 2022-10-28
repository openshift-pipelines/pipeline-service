# Documentation for consumers of Pipeline Service

This folder holds all the files required to consume Pipeline Service when the service is
operated by a third party.

## Requirements

* Access to a kcp workspace.
* The following information from the service provider:
  * Path of the kcp workspace in which the service is deployed (e.g. `root:pipeline-service`).
  * Name of the APIExport (e.g. `kubernetes`).

## Quick start guide

* Login on your kcp workspace.
* Run `./bind.sh --from root:path:to:the:service --to '~:pipeline-service'` to bind to a Pipeline Service provider.
  * See the `--help` of the command for additional options (e.g. specifying the kubeconfig file).
* A test will automatically run to validate that `pipelineruns` get scheduled.

## How to bind to the service

To bind to the service:
* Log on kcp.
* Go to the workspace in which you want to bind the service.
* Make a copy of [apibinding.yaml](./manifests/apibinding/apibinding.yaml).
* Edit `.spec.reference.workspace.path` to reference the service workspace.
* Edit `.spec.reference.workspace.exportName` to reference the name of the export.
* Apply the binding with `kubectl apply -f apibindings.yaml`

To validate that the binding is successful:
* Run `consumer/hack/run_test_workload.sh`
## How to test the service

To validate that the binding was successful:
* Login on your kcp workspace.
* Run `consumer/hack/run_test_workload.sh`.

## How to connect a repository to Pipeline as Code

TODO
