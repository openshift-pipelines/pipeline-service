This example highlights the following features:

- `credentials/compute`: multiple kubeconfigs, with multiple contexts.
- `environment/compute`: there is no constraint on how to organize the
  clusters' configuration, except that the `kustomization.yaml` for a given
  cluster must be located in a directory which name matches the name of the
  cluster as declared in the kubeconfig in `credentials/compute`.
- `environment/flavors/overlays/unstable`: customization example changing the branch from
  which the manifests used for setting up the cluster are retrieved.
