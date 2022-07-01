FROM registry.access.redhat.com/ubi8/ubi-minimal:8.6
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
COPY content /opt/access-setup
RUN chmod 755 /opt/access-setup/bin/*.sh
ENV PATH="/opt/access-setup/bin:${PATH}"
USER 65532:65532
ENV WORK_DIR /workspace
VOLUME /workspace
WORKDIR /workspace
CMD ["/opt/access-setup/setup_compute.sh"]
