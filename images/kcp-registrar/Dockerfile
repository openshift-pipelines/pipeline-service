# Build the binary
FROM golang:1.17 AS builder

WORKDIR /workspace
USER 0
RUN apt-get update && apt-get install -y jq && mkdir bin
RUN git clone https://github.com/kcp-dev/kcp.git && cd kcp && \
    BRANCH=release-0.4 && git checkout $BRANCH && \
    CGO_ENABLED=0 make

FROM registry.access.redhat.com/ubi8/ubi-minimal:8.6
LABEL build-date= \
      com.redhat.build-host= \
      description="This image provides binaries and a script to easily register clusters to kcp." \
      distribution-scope="public" \
      io.k8s.description="This image provides binaries and a script to easily register clusters to kcp." \
      io.k8s.display-name="kcp register" \
      maintainer="Pipelines Service" \
      name="kcp-registrar" \
      release="0.1" \
      summary="Provides the latest release of kcp-registrar image." \
      url="https://github.com/openshift-pipelines/pipelines-service/tree/main/images/kcp-registrar" \
      vcs-ref=  \
      vcs-type="git" \
      vendor="Pipelines Service" \
      version="0.1"
WORKDIR /
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
COPY --from=builder workspace/kcp/bin/kubectl-kcp /usr/local/bin/kubectl-kcp
RUN chmod 755 /usr/local/bin/kubectl-kcp
COPY ./register.sh /usr/local/bin/register.sh
RUN chmod 755 /usr/local/bin/register.sh
RUN JQ_VERSION=1.6 && \
    curl -sSL -o /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-$JQ_VERSION/jq-linux64 && \
    chmod 755 /usr/local/bin/jq
RUN KUBE_VERSION=v1.24.0 && \
    curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$KUBE_VERSION/bin/linux/amd64/kubectl" && \
    chmod 755 /usr/local/bin/kubectl
USER 65532:65532
VOLUME /workspace
WORKDIR /workspace
CMD ["/usr/local/bin/register.sh"]
