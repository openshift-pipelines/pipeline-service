#@FROM registry.access.redhat.com/ubi9/ubi-minimal
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:3685c58885771d2ea14608caeab6a4c3949b973588c29ce91f462b486ee1be25 AS grpc_cli
RUN set -x \
    && microdnf install -y \
        cmake-3.20.2 \
        gcc-c++-11.3.1 \
        git-2.31.1 \
        libtool-2.4.6 \
    && microdnf clean all
COPY shared /tmp/image-build/shared
RUN /tmp/image-build/shared/hack/install.sh --debug --bin grpc_cli



FROM quay.io/podman/stable:v4.3.1
RUN set -x \
    && mkdir ~/.kube \
    && mkdir -p /tmp/image-build \
    && dnf install -y \
        # gcc is needed when installing checkov's dependencies
        gcc-c++-12.2.1 \
        git-2.39.0 \
        openssl-3.0.5 \
        procps-ng-3.3.17 \
        # python3-devl is needed when installing checkov's dependencies
        python3-devel-3.11.0 \
        python3-pip-22.2.2 \
        unzip-6.0 \
        which-2.21 \
        xz-5.2.5 \
    && dnf clean all
COPY --from=grpc_cli /usr/local/bin/grpc_cli /usr/local/bin/
COPY shared /tmp/image-build/shared
RUN /tmp/image-build/shared/hack/install.sh --debug --bin argocd,bitwarden,checkov,hadolint,jq,kind,kubectl,oc,shellcheck,tkn,yamllint,yq \
    && rm -rf /tmp/image-build
WORKDIR "/workspace"
