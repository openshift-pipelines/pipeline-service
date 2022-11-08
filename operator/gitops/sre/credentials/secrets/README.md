# Secrets from secret managers

This directory contains files that store secrets from secret managers like Bitwarden, Vault, AWS Secret manager etc.
An example of such a secret could be credentials (username and password) to connect to a remote database such as AWS RDS.

The format in which the secrets need to be available in this directory is shown below:

Create a new file named `bitwarden.yaml` under secrets directory.
```
credentials:
  # tekton chains signing secrets
  - id: 1234abcd-abcd-1234-abcd-1234abcd1234
    path: credentials/manifests/compute/tekton-chains/signing-secrets.yaml
  # tekton results secrets
  - id: 1234abcd-abcd-1234-abcd-1234abcd1234
    path: credentials/manifests/compute/tekton-results/tekton-results-secret.yaml
```

Note: At the moment, only Bitwarden is supported. Please raise an issue/PR for the support of any other secret manager tools.

The contents of the file should follow the structure:
```
credentials:
  - id: 
    path: 
  - id:
    path:
```

We then parse this file (bitwarden.yaml), fetch the secret from Bitwarden based on the value of the ID and replace that secret at the value of path.

Please check [sre examples](operator/docs/sre/examples) directory for more details.
