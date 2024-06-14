#@FROM registry.access.redhat.com/ubi9/ubi-minimal
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:a7d837b00520a32502ada85ae339e33510cdfdbc8d2ddf460cc838e12ec5fa5a
RUN set -x \
    && mkdir ~/.kube \
    && mkdir -p /tmp/image-build \
    && microdnf install -y \
        httpd-tools \
        git-2.43.0 \
        make-1:4.3 \
        openssl-1:3.0.7 \
        tar-2:1.34 \
        unzip-6.0 \
        which-2.21 \
    && microdnf clean all
COPY shared /tmp/image-build/shared
RUN /tmp/image-build/shared/hack/install.sh --debug --bin bitwarden,go,jq,kubectl,oc,yq \
    && rm -rf /tmp/image-build

WORKDIR "/source"
