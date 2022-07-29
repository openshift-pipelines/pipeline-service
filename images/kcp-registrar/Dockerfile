# Build the binary
# cf https://github.com/kcp-dev/kcp/issues/1092
FROM golang:1.17 AS builder

ARG KCP_BRANCH

WORKDIR /workspace
USER 0
RUN apt-get update && apt-get install -y jq && mkdir bin
RUN git clone https://github.com/kcp-dev/kcp.git && cd kcp && \
    BRANCH=$KCP_BRANCH && git checkout $BRANCH && \
    CGO_ENABLED=0 make

FROM registry.access.redhat.com/ubi8/ubi-minimal:8.6
LABEL build-date= \
      com.redhat.build-host= \
      description="This image provides binaries and a script to easily register clusters to kcp." \
      distribution-scope="public" \
      io.k8s.description="This image provides binaries and a script to easily register clusters to kcp." \
      io.k8s.display-name="kcp register" \
      maintainer="Pipeline Service" \
      name="kcp-registrar" \
      release="0.1" \
      summary="Provides the latest release of kcp-registrar image." \
      url="https://github.com/openshift-pipelines/pipeline-service/tree/main/images/kcp-registrar" \
      vcs-ref=  \
      vcs-type="git" \
      vendor="Pipeline Service" \
      version="0.1"
WORKDIR /
RUN microdnf install findutils
ARG KCP_BRANCH
ENV KCP_SYNC_TAG=${KCP_BRANCH}
ENV HOME /tmp/home
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
RUN mkdir $HOME && chmod 777 $HOME
COPY --from=builder workspace/kcp/bin/kubectl-kcp /usr/local/bin/kubectl-kcp
RUN chmod 755 /usr/local/bin/kubectl-kcp
RUN JQ_VERSION=1.6 && \
    curl --fail -sSL -o /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-$JQ_VERSION/jq-linux64 && \
    chmod 755 /usr/local/bin/jq
RUN KUBE_VERSION=v1.24.0 && \
    curl --fail -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$KUBE_VERSION/bin/linux/amd64/kubectl" && \
    chmod 755 /usr/local/bin/kubectl
COPY ./register.sh /usr/local/bin/register.sh
RUN chmod 755 /usr/local/bin/register.sh
USER 65532:65532
VOLUME /workspace
WORKDIR /workspace
CMD ["/usr/local/bin/register.sh"]
