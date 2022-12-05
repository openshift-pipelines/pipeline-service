#@FROM registry.access.redhat.com/ubi8/ubi-minimal
FROM registry.access.redhat.com/ubi8/ubi-minimal@sha256:6910799b75ad41f00891978575a0d955be2f800c51b955af73926e7ab59a41c3
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
      url="https://github.com/openshift-pipelines/pipeline-service/tree/main/operator/images/kcp-registrar" \
      vcs-ref=  \
      vcs-type="git" \
      vendor="Pipeline Service" \
      version="0.1"
WORKDIR /
RUN microdnf install -y findutils-4.6.0 git-2.31.1 gzip-1.9 openssl-1.1.1k tar-1.30 && microdnf clean all
ARG KCP_BRANCH
ENV KCP_SYNC_TAG=${KCP_TAG}
ENV HOME /tmp/home
RUN mkdir "/workspace" && chmod 777 "/workspace" && chown 65532:65532 "/workspace"
RUN mkdir $HOME && chmod 777 $HOME

COPY shared /tmp/image-build/shared
WORKDIR /tmp/image-build/shared/hack
RUN set -x \
    && ./install.sh --bin jq,kcp,kubectl,yq \
    && rm -rf /tmp/image-build

RUN mkdir /opt/kcp-registrar
COPY operator/images/kcp-registrar/content /opt/kcp-registrar
RUN chmod 755 /opt/kcp-registrar/bin/*.sh
USER 65532:65532
VOLUME /workspace
WORKDIR /workspace
CMD ["/opt/kcp-registrar/bin/register.sh"]
