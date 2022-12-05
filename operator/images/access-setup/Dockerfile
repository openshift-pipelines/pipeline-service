#@FROM registry.access.redhat.com/ubi8/ubi-minimal
FROM registry.access.redhat.com/ubi8/ubi-minimal@sha256:6910799b75ad41f00891978575a0d955be2f800c51b955af73926e7ab59a41c3
WORKDIR /
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
ENV HOME /tmp/home
RUN mkdir $HOME && chmod 777 $HOME && chown 65532:65532 $HOME

RUN microdnf install -y gzip-1.9 tar-1.30 && microdnf clean all

COPY shared /tmp/image-build/shared
WORKDIR /tmp/image-build/shared/hack
RUN set -x \
    && ./install.sh --bin jq,kcp,kubectl \
    && rm -rf /tmp/image-build

COPY operator/images/access-setup/content /opt/access-setup
RUN chmod 755 /opt/access-setup/bin/*.sh
ENV PATH="/opt/access-setup/bin:${PATH}"
USER 65532:65532
ENV WORK_DIR /workspace
VOLUME /workspace
WORKDIR /workspace
CMD ["/opt/access-setup/bin/setup_compute.sh"]
