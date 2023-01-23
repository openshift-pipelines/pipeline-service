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


#@FROM registry.access.redhat.com/ubi9/ubi-minimal
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:3685c58885771d2ea14608caeab6a4c3949b973588c29ce91f462b486ee1be25
RUN set -x \
    && mkdir ~/.kube \
    && mkdir -p /tmp/image-build \
    && microdnf install -y \
        git-2.31.1 \
        findutils-1:4.8.0 \
        openssl-3.0.1 \
        podman-2:4.2.0 \
        procps-ng-3.3.17 \
        python3-pip-21.2.3 \
        unzip-6.0 \
        tar-2:1.34 \
        xz-5.2.5 \
    && microdnf clean all
#Installing helm as part of a work around for installing the minio operator while we sort out stale operator hub catalogs with hypershift.
#Once that has been sorted out (check with Adam), the minio requirement for helm will go away.
#NOTE: while newer versions of fedora allow dnf installation of helm, the ubi9 minimal image we have here does not.
RUN set -x \
    && mkdir -p /usr/local/bin \
    && curl -L https://mirror.openshift.com/pub/openshift-v4/clients/helm/latest/helm-linux-amd64 -o /usr/local/bin/helm \
    && chmod +x /usr/local/bin/helm
COPY --from=grpc_cli /usr/local/bin/grpc_cli /usr/local/bin/
COPY shared /tmp/image-build/shared
RUN /tmp/image-build/shared/hack/install.sh --debug --bin argocd,go,jq,kubectl,tkn,yq \
    && rm -rf /tmp/image-build
WORKDIR "/source"
