#@FROM registry.access.redhat.com/ubi9/ubi-minimal
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:2636170dc55a0931d013014a72ae26c0c2521d4b61a28354b3e2e5369fa335a3
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
