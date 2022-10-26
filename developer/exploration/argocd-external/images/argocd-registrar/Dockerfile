#FROM registry.access.redhat.com/ubi8/ubi-minimal:8.6
FROM registry.access.redhat.com/ubi8/ubi-minimal@sha256:e58664de16551db29fb0eaaeb3c4a44eaf95ad89a5b2399a1107041c4f2d6d34
LABEL build-date= \
      com.redhat.build-host= \
      description="This image provides binaries and a script to easily register clusters to Argo CD." \
      distribution-scope="public" \
      io.k8s.description="This image provides binaries and a script to easily register clusters to Argo CD." \
      io.k8s.display-name="Argo CD register" \
      maintainer="Pipeline Service" \
      name="argocd-registrar" \
      release="0.1" \
      summary="Provides the latest release of argocd-registrar image." \
      url="https://github.com/openshift-pipelines/pipeline-service/tree/main/images/argocd-registrar" \
      vcs-ref=  \
      vcs-type="git" \
      vendor="Pipeline Service" \
      version="0.1"
WORKDIR /
ENV HOME /tmp/home
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
RUN mkdir $HOME && chmod 777 $HOME
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
