FROM quay.io/podman/stable:v4.6
RUN set -x \
    && mkdir ~/.kube \
    && mkdir -p /tmp/image-build \
    && dnf install -y \
        # gcc is needed when installing checkov's dependencies
        gcc-c++-13.2.1 \
        git-2.41.0 \
        openssl-3.0.9 \
        procps-ng-3.3.17 \
        # python3-devl is needed when installing checkov's dependencies
        python3-devel-3.11.4 \
        rsync-3.2.7 \
        unzip-6.0 \
        which-2.21 \
        xz-5.4.1 \
    && dnf clean all \
    && sed -i -e "s:podman:root:" /etc/subuid /etc/subgid 
COPY shared /tmp/image-build/shared
RUN /tmp/image-build/shared/hack/install.sh --debug --bin argocd,bitwarden,checkov,hadolint,jq,kind,kubectl,oc,shellcheck,tkn,yamllint,yq \
    && rm -rf /tmp/image-build
WORKDIR "/workspace"
