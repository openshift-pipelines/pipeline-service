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
WORKDIR /
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
ENV HOME /tmp/home
RUN mkdir $HOME && chmod 777 $HOME && chown 65532:65532 $HOME
COPY --from=builder /workspace/kcp/bin/kubectl-kcp /usr/local/bin/kubectl-kcp
RUN chmod 755 /usr/local/bin/kubectl-kcp
RUN JQ_VERSION=1.6 && \
    curl -sSL -o /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-$JQ_VERSION/jq-linux64 && \
    chmod 755 /usr/local/bin/jq
RUN KUBE_VERSION=v1.24.0 && \
    curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$KUBE_VERSION/bin/linux/amd64/kubectl" && \
    chmod 755 /usr/local/bin/kubectl
COPY content /opt/access-setup
RUN chmod 755 /opt/access-setup/bin/*.sh
ENV PATH="/opt/access-setup/bin:${PATH}"
USER 65532:65532
ENV WORK_DIR /workspace
VOLUME /workspace
WORKDIR /workspace
CMD ["/opt/access-setup/bin/setup_compute.sh"]
