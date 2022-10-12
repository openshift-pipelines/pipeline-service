#FROM quay.io/podman/stable:v4
FROM quay.io/podman/stable@sha256:e968245017a54e31fec7583c589f1d68e5a14723e76d29861a887865c09084a0

RUN set -x \
    && mkdir ~/.kube \
    && mkdir -p /tmp/dockerfile \
    && dnf install -y git-2.37.3 openssl-3.0.2 procps-ng-3.3.17 unzip-6.0 which-2.21 xz-5.2.5 \
    && dnf clean all

COPY config/dependencies.yaml /tmp/dockerfile/dependencies.yaml
COPY test/images/devenv/install.sh /tmp/dockerfile/install.sh

WORKDIR /tmp/dockerfile

RUN set -x \
    && ./install.sh --dependencies ./dependencies.yaml \
    && rm -rf /tmp/dockerfile

WORKDIR "/workspace"
