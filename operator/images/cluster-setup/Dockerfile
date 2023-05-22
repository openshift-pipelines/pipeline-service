#@FROM registry.access.redhat.com/ubi9/ubi-minimal
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:b00f7556d64a698aad6cb63bb75b2692f1538926c6f619d6123cbc20a74239ec
LABEL build-date= \
      com.redhat.build-host= \
      description="This image provides binaries and a script to install tektoncd components on the workload clusters." \
      distribution-scope="public" \
      io.k8s.description="This image provides binaries and a script to install tektoncd components on the workload clusters." \
      io.k8s.display-name="cluster setup" \
      maintainer="Pipeline Service" \
      name="cluster-setup" \
      release="0.1" \
      summary="Provides the latest release of cluster-setup image." \
      url="https://github.com/openshift-pipelines/pipeline-service/tree/main/operator/images/cluster-setup" \
      vcs-ref=  \
      vcs-type="git" \
      vendor="Pipeline Service" \
      version="0.1"
WORKDIR /
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
RUN microdnf install -y \
      findutils-4.8.0 \
      git-2.39.3 \
      unzip-6.0 \
    && microdnf clean all

COPY shared /tmp/image-build/shared
RUN /tmp/image-build/shared/hack/install.sh --bin bitwarden,jq,kubectl,yq \
    && rm -rf /tmp/image-build

COPY operator/images/cluster-setup/content /opt/cluster-setup

USER 65532:65532
ENV HOME /tmp/home
RUN mkdir $HOME
VOLUME /workspace
WORKDIR /workspace
ENTRYPOINT ["/opt/cluster-setup/bin/install.sh"]
