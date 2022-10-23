#FROM registry.access.redhat.com/ubi8/ubi-minimal:8.6
FROM registry.access.redhat.com/ubi8/ubi-minimal@sha256:e58664de16551db29fb0eaaeb3c4a44eaf95ad89a5b2399a1107041c4f2d6d34
WORKDIR /
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
ENV HOME /tmp/home
RUN mkdir $HOME && chmod 777 $HOME && chown 65532:65532 $HOME

RUN microdnf install -y gzip-1.9 tar-1.30 && microdnf clean all
RUN JQ_VERSION=1.6 && \
    curl -sSL -o /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-$JQ_VERSION/jq-linux64 && \
    chmod 755 /usr/local/bin/jq
RUN KUBE_VERSION=v1.24.0 && \
    curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$KUBE_VERSION/bin/linux/amd64/kubectl" && \
    chmod 755 /usr/local/bin/kubectl
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN KCP_VERSION=v0.9.1 && \
    curl -L -o /tmp/kubectl-kcp.tgz "https://github.com/kcp-dev/kcp/releases/download/$KCP_VERSION/kubectl-kcp-plugin_$(printf '%s' "$KCP_VERSION" | sed 's/v//')_linux_amd64.tar.gz" && \
    tar -C /usr/local -xzvf /tmp/kubectl-kcp.tgz bin/kubectl-kcp && \
    rm /tmp/kubectl-kcp.tgz
COPY content /opt/access-setup
RUN chmod 755 /opt/access-setup/bin/*.sh
ENV PATH="/opt/access-setup/bin:${PATH}"
USER 65532:65532
ENV WORK_DIR /workspace
VOLUME /workspace
WORKDIR /workspace
CMD ["/opt/access-setup/bin/setup_compute.sh"]
