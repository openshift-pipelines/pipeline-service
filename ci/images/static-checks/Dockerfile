#@FROM registry.access.redhat.com/ubi9/ubi-minimal
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:3685c58885771d2ea14608caeab6a4c3949b973588c29ce91f462b486ee1be25
LABEL build-date= \
    com.redhat.build-host= \
    description="This image provides the static checks binaries." \
    distribution-scope="public" \
    io.k8s.description="This image provides the static checks binaries." \
    io.k8s.display-name="static-checks" \
    maintainer="Pipeline Service" \
    name="static-checks" \
    release="0.1" \
    summary="Provides all the binaries used for static code checks" \
    url="https://github.com/openshift-pipelines/pipeline-service/tree/main/ci/images/static-checks" \
    vcs-ref= \
    vcs-type="git" \
    vendor="Pipeline Service" \
    version="0.1"
WORKDIR /
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
ENV HOME /tmp/home
RUN mkdir $HOME && chmod 777 $HOME && chown 65532:65532 $HOME
RUN microdnf install -y findutils-4.8.0 python3-3.9.14 python3-pip-21.2.3 tar-1.34 xz-5.2.5 && \
    microdnf clean all

COPY shared /tmp/image-build/shared
WORKDIR /tmp/image-build/shared/hack
RUN set -x && \
    ./install.sh --bin checkov,hadolint,shellcheck,yamllint && \
    rm -rf /tmp/image-build

COPY ci/images/static-checks/content /opt/static-checks
RUN chmod 755 /opt/static-checks/bin/*.sh
ENV PATH="/opt/static-checks/bin:${PATH}"
USER 65532:65532
ENV WORK_DIR /workspace
VOLUME /workspace
WORKDIR /workspace
CMD ["/opt/static-checks/bin/all.sh", "--workspace_dir", "/workspace"]
