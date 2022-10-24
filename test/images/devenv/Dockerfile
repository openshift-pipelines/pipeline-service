FROM quay.io/podman/stable:v4.2.1

RUN set -x \
    && mkdir ~/.kube \
    && mkdir -p /tmp/dockerfile \
    && dnf install -y cmake-3.22.2 gcc-c++-12.0.1 git-2.37.3 libtool-2.4.6 openssl-3.0.2 procps-ng-3.3.17 unzip-6.0 which-2.21 xz-5.2.5 \
    && dnf clean all

COPY shared/config/dependencies.yaml /tmp/dockerfile/dependencies.yaml
COPY test/images/devenv/install.sh /tmp/dockerfile/install.sh

WORKDIR /tmp/dockerfile

RUN set -x \
    && ./install.sh --dependencies ./dependencies.yaml \
    && rm -rf /tmp/dockerfile

WORKDIR "/workspace"
