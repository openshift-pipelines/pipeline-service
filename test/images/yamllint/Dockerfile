FROM registry.access.redhat.com/ubi8/ubi-minimal@sha256:e58664de16551db29fb0eaaeb3c4a44eaf95ad89a5b2399a1107041c4f2d6d34
LABEL build-date= \
    com.redhat.build-host= \
    description="This image provides yamllint binary." \
    distribution-scope="public" \
    io.k8s.description="This image provides yamllint binary." \
    io.k8s.display-name="yamllint" \
    maintainer="Pipeline Service" \
    name="yamllint" \
    release="0.1" \
    summary="Provides the 1.28.0 yamllint" \
    url="https://github.com/openshift-pipelines/pipeline-service/tree/main/test/images/yamllint" \
    vcs-ref=  \
    vcs-type="git" \
    vendor="Pipeline Service" \
    version="0.1"
WORKDIR /
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
ENV HOME /tmp/home
RUN mkdir $HOME && chmod 777 $HOME && chown 65532:65532 $HOME
RUN microdnf install -y python38-3.8.12 && microdnf clean all && \
    pip3 install --no-cache-dir yamllint==1.28.0 && \
    yamllint -v
USER 65532:65532
VOLUME /workspace
WORKDIR /workspace