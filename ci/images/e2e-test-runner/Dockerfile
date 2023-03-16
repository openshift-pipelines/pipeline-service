#@FROM registry.access.redhat.com/ubi9/ubi-minimal
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:61925d31338b7b41bfd5b6b8cf45eaf80753d415b0269fc03613c5c5049b879e
RUN set -x \
    && mkdir ~/.kube \
    && mkdir -p /tmp/image-build \
    && microdnf install -y \
        httpd-tools \
        git-2.31.1 \
        make-1:4.3 \
        openssl-3.0.1 \
        tar-2:1.34 \
        unzip-6.0 \
        which-2.21 \
    && microdnf clean all
COPY shared /tmp/image-build/shared
RUN /tmp/image-build/shared/hack/install.sh --debug --bin bitwarden,go,jq,kubectl,oc,yq \
    && rm -rf /tmp/image-build

WORKDIR "/source"
