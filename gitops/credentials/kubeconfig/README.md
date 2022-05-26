# Clusters credentials 

This directory and sub-directories' purpose is to contain the kubeconfig files used for registering the clusters to Argo CD.

The name of the kubeconfig file must match the name of the
cluster configuration directory. E.g. if the configuration
directory is `environment/compute/some/path/my-cluster`, then the
kubeconfig should be `credentials/kubeconfig/compute/my-cluster.yaml`.

---
**_NOTES:_**

The information contained in kubeconfig files is confidential. Measures should be taken to protect it from being disclosed. This directory and sub-directories should not contain these files in a public repository. Don't forget to amend the `.gitignore` file if you want to add other files to a private fork of this repository.

---
