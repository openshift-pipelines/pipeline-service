This example highlights the following features:

- `credentials/compute`: there is a single kubeconfig, with a single context
  referencing a single cluster `mycluster-com`.
- `environment/compute`: a single directory which name matches the name of the
  cluster as specified in the `credentials/compute`, with a `kustomization.yaml`
  specifying the configuration to apply.
