FROM quay.io/podman/stable:v4.3.1
RUN set -x \
    && mkdir ~/.kube \
    && mkdir -p /tmp/image-build \
    && dnf install -y \
        # gcc is needed when installing checkov's dependencies
        gcc-c++-12.2.1 \
        git-2.39.2 \
        openssl-3.0.5 \
        procps-ng-3.3.17 \
        # python3-devl is needed when installing checkov's dependencies
        python3-devel-3.11.2 \
        python3-pip-22.2.2 \
        unzip-6.0 \
        which-2.21 \
        xz-5.4.1 \
    && dnf clean all
COPY shared /tmp/image-build/shared
RUN /tmp/image-build/shared/hack/install.sh --debug --bin argocd,bitwarden,checkov,hadolint,jq,kind,kubectl,oc,shellcheck,tkn,yamllint,yq \
    && rm -rf /tmp/image-build
WORKDIR "/workspace"
