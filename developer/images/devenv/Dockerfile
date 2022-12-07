#@FROM registry.access.redhat.com/ubi8/ubi-minimal
FROM registry.access.redhat.com/ubi8/ubi-minimal@sha256:4ed971a5564d2cfedf750793da53ef6f1fdf295263f1cc31d703aa8acf6d02cf AS grpc_cli
RUN set -x \
    && microdnf install -y \
        cmake-3.20.2 \
        gcc-c++-8.5.0 \
        git-2.31.1 \
        libtool-2.4.6 \
    && microdnf clean all
COPY shared /tmp/image-build/shared
RUN /tmp/image-build/shared/hack/install.sh --debug --bin grpc_cli


FROM quay.io/podman/stable:v4.2.1

RUN set -x \
    && mkdir ~/.kube \
    && mkdir -p /tmp/image-build \
    && dnf install -y \
        git-2.38.1 \
        openssl-3.0.2 \
        procps-ng-3.3.17 \
        python3-pip-21.3.1 \
        unzip-6.0 \
        which-2.21 \
        xz-5.2.5 \
    && dnf clean all

COPY shared /tmp/image-build/shared
COPY --from=grpc_cli /usr/local/bin/grpc_cli /usr/local/bin/
RUN /tmp/image-build/shared/hack/install.sh --debug --bin argocd,bitwarden,checkov,hadolint,jq,kind,kubectl,oc,shellcheck,tkn,yamllint,yq \
    && rm -rf /tmp/image-build

WORKDIR "/workspace"
