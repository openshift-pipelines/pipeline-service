# Gateway for Tekton triggers and Pipelines as Code

Leveraging kcp, workload clusters are an infrastructure that end users may not be aware of. Depending on circumstances their pipelines may get scheduled on one or another cluster.
With the approach described for [phase 1](../README.md#phase-1) controllers are directly running on these workload clusters.

This introduces a challenge. For trigger integration, external systems or users need to send requests to the listeners on the workload cluster.
The approach taken for addressing it is to introduce a gateway (an haproxy container) that forwards the requests to listeners part of the workload cluster infrastructure.

## Architecture

![Gateway architecture](./images/haproxy.png)

- GLB is [kcp global load balancer](https://github.com/Kuadrant/kcp-glbc). This is a work in progress. The current version automatically configures DNS, e.g. route 53, so that the hostname points to the ingress endpoint of the cluster where the matching workload (Service, Deployment) has been deployed. It also integrates with cert-manager to configure a certificate that matches the hostname.
- Ingress, Service, Deployment and ConfigMap for the HAProxy based gateway are created in kcp, which syncs them onto the workload clusters.

The request flow is as follows:

1. An external system, GitHub for instance, triggers an http call.
2. The DNS server returns the IP address for the ingress router running on the same workload cluster (or a proxy to it) as the gateway.
3. The ingress router forwards the call to its backend the gateway (HAProxy container).
4. HAProxy uses path-based routing to forward `/trigger` requests to the Pipelines as Code Service.
5. The Service, implemented through iptables rules or a cloud provider's load balancer most of the time, forwards the packets to the trigger pod.
6. The trigger pod processes the request.

## Installation

### Prerequisites

[kcp GLBC](https://github.com/Kuadrant/kcp-glbc) must be deployed. [Instructions](https://github.com/Kuadrant/kcp-glbc/blob/main/docs/deployment.md) are provided in its GitHub repository.

### Commands

Kubectl should point to your kcp organisation.

```bash
kubectl kcp workspace create infra --enter
kubectl create -f ./gitops/argocd/triggers/gateway/haproxy-cfg-cm.yaml
kubectl create -f ./gitops/argocd/triggers/gateway/haproxy-deployment.yaml
kubectl create -f ./gitops/argocd/triggers/gateway/haproxy-service.yaml
kubectl create -f ./gitops/argocd/triggers/gateway/haproxy-ingress.yaml
```

HAProxy configuration can be amended through the ConfigMap. See the section below.

## Configuration

Connection settings, support for https can be configured by amending the HAProxy configuration contained in the ConfigMap.
This will get streamlined with the automation of the installation of Tekton triggers.

The first use case for the gateway is to forward requests to the EventListener for Pipelines as Code. This may also be used to proxy other services.
Therefore, additional frontends can be configured so that queries with other paths are forwarded to other backend servers.

Path-based routing is configured in this snippet:

```bash
acl PATH_pac path_beg -i /pac/
use_backend be_el_pac if PATH_pac
```

The backend in charge of processing the query can be specified in the referenced section:

```bash
server el-pac el-pipelines-as-code-interceptor.openshift-pipelines.svc.cluster.local:8080
```

here the backend is the service `el-pipelines-as-code-interceptor` in the `openshift-pipelines` namespace listening to port 8080.

## Demo

**Demo** (3mns)

[![asciicast](https://asciinema.org/a/098vFj4chE51xa6xIKbNzAOdl.svg)](https://asciinema.org/a/098vFj4chE51xa6xIKbNzAOdl)

---

**_NOTE:_**  This is only needed for phase 1. This component will get removed when we move to phase 2 and have the event listeners provisioned through kcp.

---

## Limitations

- There is currently no controller watching EventListeners to configure the gateway dynamically. This means that the gateway would work for Pipelines as Code, which offers a stable entrypoint but not for pure Tekton Triggers.
- PipelineRuns are not visible in any kcp workspace.

