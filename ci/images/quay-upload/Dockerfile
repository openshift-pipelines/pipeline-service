#FROM registry.access.redhat.com/ubi8/ubi-minimal:8.7-923
FROM registry.access.redhat.com/ubi8/ubi-minimal@sha256:4ed971a5564d2cfedf750793da53ef6f1fdf295263f1cc31d703aa8acf6d02cf
LABEL build-date= \
      com.redhat.build-host= \
      description="This image provides binaries and a script to tag images with the latest commit ID on quay.io" \
      distribution-scope="public" \
      io.k8s.description="This image provides binaries and a script to tag images with the latest commit ID on quay.io" \
      io.k8s.display-name="quay-upload" \
      maintainer="Pipeline Service" \
      name="quay-upload" \
      release="0.1" \
      summary="Providea a script to tag images with the latest commit ID on quay.io" \
      url="" \
      vcs-ref=  \
      vcs-type="git" \
      vendor="Pipeline Service" \
      version="0.1"
WORKDIR /
RUN mkdir /workspace && chmod 777 /workspace && chown 65532:65532 /workspace
ENV HOME /tmp/home
RUN mkdir $HOME && chmod 777 $HOME && chown 65532:65532 $HOME
RUN JQ_VERSION="1.6" && \
    curl -sSL -o "/usr/local/bin/jq" "https://github.com/stedolan/jq/releases/download/jq-$JQ_VERSION/jq-linux64" && \
    chmod 755 "/usr/local/bin/jq"
COPY image-upload.sh /usr/local/bin/image-upload.sh
RUN chmod 755 /usr/local/bin/image-upload.sh
USER 65532:65532
VOLUME /workspace
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/image-upload.sh"]
