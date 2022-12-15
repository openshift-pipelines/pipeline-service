#@FROM registry.access.redhat.com/ubi9/ubi-minimal
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:3685c58885771d2ea14608caeab6a4c3949b973588c29ce91f462b486ee1be25
LABEL build-date= \
    com.redhat.build-host= \
    description="This image provides the scripts to update the repository dependencies." \
    distribution-scope="public" \
    io.k8s.description="This image provides the scripts to update the repository dependencies." \
    io.k8s.display-name="dependencies-update" \
    maintainer="Pipeline Service" \
    name="dependencies-update" \
    release="0.1" \
    summary="Provides the scripts to update the repository dependencies" \
    url="https://github.com/openshift-pipelines/pipeline-service/tree/main/developer/images/dependencies-update" \
    vcs-ref= \
    vcs-type="git" \
    vendor="Pipeline Service" \
    version="0.1"
WORKDIR /
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
ENV HOME /tmp/home
RUN mkdir $HOME && chmod 777 $HOME && chown 65532:65532 $HOME
RUN microdnf install -y \
      findutils-4.8.0 && \
    microdnf clean all

COPY developer/images/dependencies-update/content /opt/dependencies-update
RUN chmod 755 /opt/dependencies-update/bin/*.sh
ENV PATH="/opt/dependencies-update/bin:${PATH}"
USER 65532:65532
ENV WORK_DIR /workspace
VOLUME /workspace
WORKDIR /workspace
CMD ["/opt/dependencies-update/bin/update.sh", "--workspace_dir", "/workspace"]
