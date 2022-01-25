#use golang as base image and compile kcp
FROM golang:1.17 as src

LABEL usage="using multi-stage build to compile kcp using go"

WORKDIR /go/src/app
RUN git clone https://github.com/kcp-dev/kcp.git && cd ./kcp && git checkout ae4e07fcd4399264dccab47509ef17f2851050ee

WORKDIR /go/src/app/kcp
RUN go build -ldflags "-X k8s.io/component-base/version.gitVersion=v1.22.2 -X k8s.io/component-base/version.gitCommit=5e58841cce77d4bc13713ad2b91fa0d961e69192" -o bin/kcp ./cmd/kcp

FROM fedora:latest

LABEL comments="Dockerfile to run kcp inside a container"

#install git
RUN dnf -y install git

#install wget
RUN dnf -y install wget

#install ps
RUN dnf -y install procps

#install kubectl
WORKDIR /workspace
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
RUN sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

WORKDIR /workspace
#copy the golang compiled kcp application from the src builder to our main docker image
COPY --from=src /go/src/app/kcp kcp
COPY entry.sh .

ENTRYPOINT ["./entry.sh"]