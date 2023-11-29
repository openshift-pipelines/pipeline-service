#@FROM registry.access.redhat.com/ubi9/ubi-minimal
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:c77792b8084ce5946c68f39024fa460ef7769c0eef3fce995e70299e21a7e166
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
