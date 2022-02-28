#use golang as base image and compile kcp
FROM golang:1.17 as src

WORKDIR /go/src/app
RUN git clone https://github.com/kcp-dev/kcp.git && cd ./kcp && git checkout 986710c754ed0dac9ae1525661de931e5dd7c0cc

WORKDIR /go/src/app/kcp
RUN go build -ldflags "-X k8s.io/component-base/version.gitVersion=v1.22.2 -X k8s.io/component-base/version.gitCommit=5e58841cce77d4bc13713ad2b91fa0d961e69192" -o bin/kcp ./cmd/kcp

FROM fedora:latest

WORKDIR /workspace
#copy the golang compiled kcp application from the src builder to our main docker image
COPY --from=src /go/src/app/kcp kcp
COPY entry.sh .

ENTRYPOINT ["./entry.sh"]