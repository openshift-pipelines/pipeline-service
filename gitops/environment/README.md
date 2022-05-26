# Clusters configuration

This directory and sub-directories' purpose is to contain the
configuration files used to deploy Pipelines Service to the
clusters.

The configuration for a single cluster is created by creating
a `$cluster_name` folder under `environment/compute` and putting
the appropriate `kustomization.yaml` in that directory.

To manage large environment, it is possible to nest configurations inside multiple level of directories. I.e.
`environment/compute/private_cloud/my-project/my-cluster/kustomization.yaml`
is a valid configuration for `my-cluster`.
