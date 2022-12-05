#@FROM registry.access.redhat.com/ubi8/ubi-minimal
FROM registry.access.redhat.com/ubi8/ubi-minimal@sha256:6910799b75ad41f00891978575a0d955be2f800c51b955af73926e7ab59a41c3
LABEL build-date= \
    com.redhat.build-host= \
    description="This image provides shellcheck binary." \
    distribution-scope="public" \
    io.k8s.description="This image provides shellcheck binary." \
    io.k8s.display-name="shellcheck" \
    maintainer="Pipeline Service" \
    name="shellcheck" \
    release="0.1" \
    summary="Provides the 0.8.0 shellcheck" \
    url="https://github.com/openshift-pipelines/pipeline-service/tree/main/ci/images/shellcheck" \
    vcs-ref=  \
    vcs-type="git" \
    vendor="Pipeline Service" \
    version="0.1"
WORKDIR /
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
ENV HOME /tmp/home
RUN mkdir $HOME && chmod 777 $HOME && chown 65532:65532 $HOME
RUN microdnf install -y tar-1.30 xz-5.2.4 findutils-4.6.0 && microdnf clean all

COPY shared /tmp/image-build/shared
WORKDIR /tmp/image-build/shared/hack
RUN set -x \
    && ./install.sh --bin shellcheck \
    && rm -rf /tmp/image-build

USER 65532:65532
VOLUME /workspace
WORKDIR /workspace