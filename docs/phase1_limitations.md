# Phase 1 Limitations


## ServiceAccount used by TaskRuns and PipelineRuns
The `default` SA in kcp workspace has the secret containing its token synchronised in the workload cluster but under a different name (with `kcp` prefix). In phase 1 we don't want Tekton pods to communicate with the kcp API. As such they should not use an SA and its token created by kcp. This is a limitation but an existing SA from the workload cluster can be used instead.

### Instructions
When you create a TaskRun or a PipelineRun you have the following options:
* Not specifying an SA is valid
* The `pipeline` SA can be used
* The `default` SA does not work as it would point to the KCP API
* A custom SA created in kcp workspace may have the same flaw for our phase 1 approach