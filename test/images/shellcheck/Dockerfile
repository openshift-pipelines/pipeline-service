FROM registry.access.redhat.com/ubi8/ubi-minimal:8.6
LABEL build-date= \
    com.redhat.build-host= \
    description="This image provides shellcheck binary." \
    distribution-scope="public" \
    io.k8s.description="This image provides shellcheck binary." \
    io.k8s.display-name="shellcheck" \
    maintainer="Pipelines Service" \
    name="shellcheck" \
    release="0.1" \
    summary="Provides the 0.7.1 shellcheck" \
    url="https://github.com/openshift-pipelines/pipelines-service/tree/main/images/shellcheck" \
    vcs-ref=  \
    vcs-type="git" \
    vendor="Pipelines Service" \
    version="0.1"
WORKDIR /
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
ENV HOME /tmp/home
RUN mkdir $HOME && chmod 777 $HOME && chown 65532:65532 $HOME
RUN microdnf install tar xz findutils
RUN SHELLCHECK_VERSION=0.7.1 && \
    curl --fail -sSL  https://github.com/koalaman/shellcheck/releases/download/v$SHELLCHECK_VERSION/shellcheck-v$SHELLCHECK_VERSION.linux.x86_64.tar.xz | tar -xJvf - shellcheck-v$SHELLCHECK_VERSION/shellcheck && \
    mv shellcheck-v$SHELLCHECK_VERSION/shellcheck /usr/local/bin/shellcheck && \
    chmod 755 /usr/local/bin/shellcheck && \
    shellcheck -V
USER 65532:65532
VOLUME /workspace
WORKDIR /workspace