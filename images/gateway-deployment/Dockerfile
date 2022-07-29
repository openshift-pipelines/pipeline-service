FROM registry.access.redhat.com/ubi8/ubi-minimal:8.6
LABEL build-date= \
      com.redhat.build-host= \
      description="This image provides binaries and a script to deploy gateway on kcp." \
      distribution-scope="public" \
      io.k8s.description="This image provides binaries and a script to deploy gateway on kcp." \
      io.k8s.display-name="gateway deployment" \
      maintainer="Pipeline Service" \
      name="gateway-deployment" \
      release="0.1" \
      summary="Provides the latest release of gateway-deployment image." \
      url="https://github.com/openshift-pipelines/pipeline-service/tree/main/images/gateway-deployment" \
      vcs-ref=  \
      vcs-type="git" \
      vendor="Pipeline Service" \
      version="0.1"
WORKDIR /
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
ENV HOME /tmp/home
RUN mkdir $HOME && chmod 777 $HOME && chown 65532:65532 $HOME
COPY ./install.sh /usr/local/bin/install.sh
RUN KUBE_VERSION=v1.24.0 && \
    curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$KUBE_VERSION/bin/linux/amd64/kubectl" && \
    chmod 755 /usr/local/bin/kubectl
USER 65532:65532
VOLUME /workspace
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/install.sh"]
