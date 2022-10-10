#FROM registry.access.redhat.com/ubi8/ubi-minimal:8.6
FROM registry.access.redhat.com/ubi8/ubi-minimal@sha256:e58664de16551db29fb0eaaeb3c4a44eaf95ad89a5b2399a1107041c4f2d6d34
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
RUN JQ_VERSION=1.6 && \
    curl -sSL -o /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-$JQ_VERSION/jq-linux64 && \
    chmod 755 /usr/local/bin/jq
RUN KUBE_VERSION=v1.24.0 && \
    curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$KUBE_VERSION/bin/linux/amd64/kubectl" && \
    chmod 755 /usr/local/bin/kubectl
RUN microdnf install -y findutils-4.6.0 git-2.31.1 && microdnf clean all
COPY bin /usr/local/bin
RUN chmod 755 /usr/local/bin/install.sh /usr/local/bin/utils.sh
USER 65532:65532
VOLUME /workspace
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/install.sh"]
