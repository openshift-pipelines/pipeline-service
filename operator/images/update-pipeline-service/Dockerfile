#@FROM registry.access.redhat.com/ubi9/ubi-minimal
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:61925d31338b7b41bfd5b6b8cf45eaf80753d415b0269fc03613c5c5049b879e
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

COPY shared /tmp/image-build/shared
WORKDIR /tmp/image-build/shared/hack
RUN set -x \
    && ./install.sh --bin jq,yq \
    && rm -rf /tmp/image-build

COPY operator/images/update-pipeline-service/content /opt/update-pipeline-service
USER 65532:65532
VOLUME /workspace
WORKDIR /workspace
ENTRYPOINT ["/opt/update-pipeline-service/bin/update.sh"]
