# Documentation for consumers of Pipeline Service

This folder holds all the files required to consume Pipeline Service when the service is operated by a third party.

## Requirements

* Access to a kcp workspace.
* The following information from the service provider:
  * Path of the kcp workspace in which the service is deployed (e.g. `root:pipeline-service`).
  * Name of the APIExport (e.g. `kubernetes`).

## Quick start guide

This section explains how to use the provided scripts to quickly setup a workspace to use a service provided by an operator of Pipeline Service.

If you prefer to do it yourself, or something is not quite working the way it should, see the `Manual setup` section to be walked through the procedure.

### Binding to the service

* Login to your kcp workspace (e.g. `~`).
* Run `./bind.sh --exportname 'kubernetes' --from 'root:path:to:the:service' --to '~:pipeline-service'`
  * A new `pipeline-service` workspace will be created under `~`.
  * The binding to the Pipeline Service provider will be created in the `~:pipeline-service` workspace.
  * A test will automatically be run to validate that `pipelineruns` get scheduled.
  * See the `--help` of the command for additional options (e.g. specifying the kubeconfig file).

### Connecting a repository to Pipelines as Code

TODO

## Manual setup

This section is unnecessary if you've already followed the steps of the `Quick start guide`.

### How to bind to the service

To bind to the service:
* Login to kcp.
* Go to the workspace in which you want to bind the service.
* Make a copy of [apibinding.yaml](./manifests/apibinding/apibinding.yaml).
* Edit `.spec.reference.workspace.path` to reference the service workspace.
* Edit `.spec.reference.workspace.exportName` to reference the name of the export.
* Apply the binding with `kubectl apply -f apibindings.yaml`

To validate that the binding is successful:
* Run `consumer/hack/run_test_workload.sh`
### How to test the service

To validate that the binding was successful:
* Login to your kcp workspace.
* Run `consumer/hack/run_test_workload.sh`.

### How to connect a repository to Pipeline as Code

TODO
