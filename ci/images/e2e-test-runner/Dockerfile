#@FROM registry.access.redhat.com/ubi9/ubi-minimal
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:b330d9e6aa681d5fe2b11fcfe0ca51e1801d837dd26804b0ead9a09ca8246c40
RUN set -x \
    && mkdir ~/.kube \
    && mkdir -p /tmp/image-build \
    && microdnf install -y \
        httpd-tools \
        git-2.39.3 \
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
