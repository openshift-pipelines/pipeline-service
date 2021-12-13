# Pipelines-service

Running Tekton and friends on top of KCP!

## Hacks

1. All Tekton CRDs are installed on KCP

Tekton controller requires all of them to be installed to work.

Future: only TaskRun and PipelineRun will be available

2. TaskRun controller adds itself the `kcp.dev/cluster` annotation to the Pod.

There is no component in KCP that place Pods on the correct cluster

Future: there will be a controller like the deployment splitter but for pods

3. Disable injected sidecar feature in Tekton

By default, Tekton TaskRun controller creates pods that wait for a particular annotation before starting.
This annotation is added by the controller once all init containers have run. 

This annotation is not propagated by the KCP syncer, maybe something to change. A quick fix is to disable this feature.

Future: KCP syncer will handle this and propagate new annotations.
