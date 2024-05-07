#@FROM registry.access.redhat.com/ubi9/ubi-minimal
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:2636170dc55a0931d013014a72ae26c0c2521d4b61a28354b3e2e5369fa335a3
RUN set -x \
    && mkdir ~/.kube \
    && mkdir -p /tmp/image-build \
    && microdnf install -y \
        gettext-0.21 \
        git-2.43.0 \
        findutils-1:4.8.0 \
        openssl-1:3.0.7 \
        podman-4:4.9.4 \
        procps-ng-3.3.17 \
        python3-pip-21.2.3 \
        rsync-3.2.3 \
        unzip-6.0 \
        tar-2:1.34 \
        xz-5.2.5 \
    && microdnf clean all
COPY shared /tmp/image-build/shared
RUN /tmp/image-build/shared/hack/install.sh --debug --bin argocd,aws,bitwarden,go,jq,kubectl,oc,rosa,terraform,tkn,yq \
    && rm -rf /tmp/image-build
WORKDIR "/source"
