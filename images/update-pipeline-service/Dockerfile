FROM registry.access.redhat.com/ubi8/ubi-minimal:8.6
LABEL build-date= \
      com.redhat.build-host= \
      description="This image provides the required tooling to update the image tags on the SRE gitops repository" \
      distribution-scope="public" \
      io.k8s.description="This image provides the required tooling to update the image tags on the SRE gitops repository" \
      io.k8s.display-name="upgrade gitlab" \
      maintainer="Pipeline Service" \
      name="upgrade-gitlab" \
      release="0.1" \
      summary="Updates the image tags on the SRE gitops repository" \
      url="" \
      vcs-ref=  \
      vcs-type="git" \
      vendor="Pipeline Service" \
      version="0.1"
WORKDIR /
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
ENV HOME /tmp/home
RUN mkdir $HOME && chmod 777 $HOME && chown 65532:65532 $HOME
RUN YQ_VERSION="v4.24.5" && \
    curl --fail -sSL -o "/usr/local/bin/yq" "https://github.com/mikefarah/yq/releases/download/$YQ_VERSION/yq_linux_amd64" && \
    chmod 755 "/usr/local/bin/yq"
RUN JQ_VERSION="1.6" && \
    curl -sSL -o "/usr/local/bin/jq" "https://github.com/stedolan/jq/releases/download/jq-$JQ_VERSION/jq-linux64" && \
    chmod 755 "/usr/local/bin/jq"
COPY ./bin /usr/local/bin
RUN chmod 755 /usr/local/bin/gitlab_open_mr.sh && chmod 755 /usr/local/bin/update.sh
USER 65532:65532
VOLUME /workspace
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/update.sh"]
