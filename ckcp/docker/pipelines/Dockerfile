FROM golang:1.17 as src

WORKDIR /workspace
RUN git clone https://github.com/tektoncd/pipeline.git && cd pipeline && git checkout v0.32.0
RUN git clone https://github.com/openshift-pipelines/pipelines-service.git

# label.patch : Pods need to be placed on a physical cluster. Adding the label manually for that purpose.
# pipeline-ff.patch : This feature unblocks Tekton pods. The READY annotation is not correctly propagated to the physical cluster.
# remove-conversion.patch : Conversion is not working yet on KCP
WORKDIR /workspace/pipeline
RUN git apply ../pipelines-service/pipeline-ff.patch && git apply ../pipelines-service/remove-conversion.patch

RUN make bin/controller

FROM fedora:latest

WORKDIR /workspace
COPY --from=src /workspace/pipeline /workspace/pipeline

COPY entry.sh .
ENTRYPOINT ["./entry.sh"]