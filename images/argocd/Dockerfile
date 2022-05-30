FROM registry.access.redhat.com/ubi8/ubi-minimal:8.6
WORKDIR /
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
# Select desired TAG from https://github.com/argoproj/argo-cd/releases
COPY ./register.sh /usr/local/bin/register.sh
RUN JQ_VERSION=1.6 &&\
    curl -sSL -o /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-$JQ_VERSION/jq-linux64 && \
    chmod +755 /usr/local/bin/jq
RUN ARGO_VERSION=v2.3.3 && \
    curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/$ARGO_VERSION/argocd-linux-amd64 && \
    chmod +755 /usr/local/bin/argocd
RUN KUBE_VERSION=v1.24.0 && \
    curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$KUBE_VERSION/bin/linux/amd64/kubectl" && \
    chmod +755 /usr/local/bin/kubectl
USER 65532:65532
VOLUME /workspace
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/register.sh"]
