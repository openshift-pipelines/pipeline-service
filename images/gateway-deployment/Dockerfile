#FROM registry.access.redhat.com/ubi8/ubi-minimal:8.6
FROM registry.access.redhat.com/ubi8/ubi-minimal@sha256:e58664de16551db29fb0eaaeb3c4a44eaf95ad89a5b2399a1107041c4f2d6d34
LABEL build-date= \
      com.redhat.build-host= \
      description="This image provides binaries and a script to deploy the gateway component on kcp." \
      distribution-scope="public" \
      io.k8s.description="This image provides binaries and a script to deploy the gateway component on kcp." \
      io.k8s.display-name="gateway deployment" \
      maintainer="Pipeline Service" \
      name="gateway-deployment" \
      release="0.1" \
      summary="Provides the latest release of the gateway-deployment image." \
      url="https://github.com/openshift-pipelines/pipeline-service/tree/main/images/gateway-deployment" \
      vcs-ref=  \
      vcs-type="git" \
      vendor="Pipeline Service" \
      version="0.1"
WORKDIR /
RUN microdnf install -y gzip-1.9 tar-1.30 git-2.31.1 && microdnf clean all
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
ENV HOME /tmp/home
RUN mkdir $HOME && chmod 777 $HOME && chown 65532:65532 $HOME
COPY ./install.sh /usr/local/bin/install.sh
RUN KUBE_VERSION=v1.24.0 && \
    curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$KUBE_VERSION/bin/linux/amd64/kubectl" && \
    chmod 755 /usr/local/bin/kubectl
RUN KCP_VERSION_SHORT="0.9.0" && \
    KCP_VERSION="v$KCP_VERSION_SHORT" && \
    curl --fail -sSL -o "/tmp/kubectl-kcp.tgz" "https://github.com/kcp-dev/kcp/releases/download/$KCP_VERSION/kubectl-kcp-plugin_${KCP_VERSION_SHORT}_linux_amd64.tar.gz" && \
    tar -C "/usr/local" -xzvf "/tmp/kubectl-kcp.tgz" "bin/kubectl-kcp" && \
    rm "/tmp/kubectl-kcp.tgz"
USER 65532:65532
VOLUME /workspace
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/install.sh"]
