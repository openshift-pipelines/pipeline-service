#@FROM registry.access.redhat.com/ubi9/ubi-minimal
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:0dfa71a7ec2caf445e7ac6b7422ae67f3518960bd6dbf62a7b77fa7a6cfc02b1
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
