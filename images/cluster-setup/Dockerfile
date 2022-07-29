FROM registry.access.redhat.com/ubi8/ubi-minimal:8.6
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
      url="https://github.com/openshift-pipelines/pipeline-service/tree/main/images/cluster-setup" \
      vcs-ref=  \
      vcs-type="git" \
      vendor="Pipeline Service" \
      version="0.1"
WORKDIR /
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
ENV HOME /tmp/home
RUN mkdir $HOME && chmod 777 $HOME && chown 65532:65532 $HOME
RUN KUBE_VERSION=v1.24.0 && \
    curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$KUBE_VERSION/bin/linux/amd64/kubectl" && \
    chmod 755 /usr/local/bin/kubectl
RUN microdnf install findutils git
COPY ./install.sh /usr/local/bin/install.sh
USER 65532:65532
VOLUME /workspace
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/install.sh"]
