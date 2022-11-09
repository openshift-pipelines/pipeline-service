FROM quay.io/podman/stable:v4.2.1

RUN set -x \
    && mkdir ~/.kube \
    && mkdir -p /tmp/image-build \
    && dnf install -y \
        cmake-3.22.2 \
        gcc-c++-12.0.1 \
        git-2.38.1 \
        libtool-2.4.6 \
        openssl-3.0.2 \
        procps-ng-3.3.17 \
        python3-pip-21.3.1 \
        unzip-6.0 \
        which-2.21 \
        xz-5.2.5 \
    && dnf clean all

COPY shared /tmp/image-build/shared

WORKDIR /tmp/image-build/shared/hack

RUN ./install.sh --debug --bin argocd,bitwarden,grpc_cli,hadolint,jq,kcp,kind,kubectl,oc,shellcheck,tkn,yamllint,yq \
    && rm -rf /tmp/image-build

WORKDIR "/workspace"
