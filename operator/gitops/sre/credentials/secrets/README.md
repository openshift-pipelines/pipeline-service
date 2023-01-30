# Secrets from secret managers

This directory contains files that store secrets from secret managers like Bitwarden, Vault, AWS Secret manager etc.
An example of such a secret could be credentials (username and password) to connect to a remote database such as AWS RDS.

The contents of the file under secrets directory should follow the below structure:
```
credentials:
  - id: 
    path: 
  - id:
    path:
```

### Bitwarden Example

Create a new file named `bitwarden.yaml` under secrets directory and provide a list of id & path values for each secret.
```
credentials:
  # tekton chains signing secrets
  - id: 1234abcd-abcd-1234-abcd-1234abcd1234
    path: credentials/manifests/compute/tekton-chains/signing-secrets.yaml
  # tekton results secrets
  - id: 1234abcd-abcd-1234-abcd-1234abcd1235
    path: credentials/manifests/compute/tekton-results/tekton-results-secret.yaml
  # minio S3 storage secret
  - id: 1234abcd-abcd-1234-abcd-1234abcd1236
    path: credentials/manifests/compute/tekton-results/tekton-results-minio-secret.yaml
```

- At the moment, only Bitwarden is supported. Please raise an issue/PR for the support of any other secret manager tools.
- The secret stored in the secret manager tools must be the content of the file you're trying to protect in base64 encoded form.
- We then parse the file, fetch the secret from Bitwarden based on the value of the ID and replace that secret at the value of path.

Notice: In the Bitwarden you should pre-create vault items with secrets manually. You can do that using web user interface or cli: [bw create item](https://bitwarden.com/help/cli/#create). Secret value should be stored in the "password" field of the vault item (and encoded in the base64 like mentioned above). Also You can use command `bw list items` to retrieve detailed json with id information. But this command returns cached results for the login session. To get actual information,
you should make re-login: `bw logout` and `bw login` and then execute `bw list items`.

Please check [sre examples](operator/docs/sre/examples) directory for more details.
