# Pipelines-service

Running Tekton and friends on top of KCP!

## Run

The script `run.sh` is tailored for macOS with Docker Desktop.

The Tekton Triggers part works because Docker Desktop allows containers to call services on the host with `host.docker.internal`.
Please update the script to the correct DNS name on your system.

## Hacks for vanilla Tekton

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

4. KCP version needs to be set

Tekton pipeline controller checks the version of the apiserver. It needs to satisfy a particular regexp.
The default value doesn't work.

Future: KCP will have a proper version set.

5. TaskRun logs are not available

Future: Pod will be a first-class citizen of KCP?

## Hacks for Tekton Triggers

1. Tekton CRDs must not contain `conversion` in their definition.

EventListener, when it calls KCP API, triggers a ConversionReview if this field is present.
KCP panics if it receives this.

Future: Webhooks will be supported by KCP.

2. Interceptors are not supported yet.

Future: To be fixed by us.

3. Service Account for Event Listener is handled manually

Triggers controller manages EL deployments. It uses service accounts for EL to call back apiserver. 
This doesn't work currently with KCP. 

Future: Service accounts will be copied to physical cluster somehow. This is needed for operators anyway.

4. Port forwarding only works on the physical cluster (only needed for testing)

Future: Pod will be a first-class citizen of KCP?
