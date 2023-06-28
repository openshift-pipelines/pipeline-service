# Pipeline Service Observability

This deploys observability (o11y) components used to configure Prometheus and
Grafana. It utilizes the o11y stack from redhat-appstudio, with modifications
to only deploy what is needed by the Pipeline Service for GitOps-based
development.

## GitOps Inner Loop Development

The `dev_setup.sh` configures Prometheus and Grafana to deploy the Pipeline
Service dashboards. Grafana's UI can be accessed at the
`grafana-access-appstudio-grafana.apps...` route on your cluster.

To iterate on your dashboard (deploying with `--use-current-branch`):

1. Navigate to the Pipeline Service dashboard in Grafana.
2. Add the panels and/or rows for your metrics as desired.
3. Click the "Share" icon to save the dashboard to JSON.
4. Copy the JSON into the pipeline-service-dashboard.json file, located in
   `operator/gitops/argocd/grafana/dashboards`.
5. Commit the updated JSON, push to your branch, and verify the dashboard is
   updated once ArgoCD syncs your repository.

## Components

### appstudio-prometheus

This configures the Red Hat
[Observability Operator](https://github.com/rhobs/observability-operator) using
the same manifests used by App Studio. The operator consolidates the "cluster
monitoring" and "user workload" monitoring stacks, allowing metrics to combined
in a single data source view.

### appstudio-grafana

This configures the [Grafana Operator](https://github.com/grafana-operator/grafana-operator)
using the same manifests as App Studio. The operator deploys and manages
Grafana instances, and lets dashboards be configured with custom resources and
JSON stored in ConfigMaps. The deployment includes the Pipeline Service
dashboard, which is referenced in-tree.
