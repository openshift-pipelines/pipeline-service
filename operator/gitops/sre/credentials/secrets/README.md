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
  # tekton results secrets
  - id: c55e17ac-cc15-4455-aabe-af8d000be7ae
    path: credentials/manifests/compute/tekton-results/tekton-results-secret.yaml
  # minio S3 storage secret
  - id: 676f75cb-4855-46c6-8b3e-af8d003c1c0c
    path: credentials/manifests/compute/tekton-results/tekton-results-minio-secret.yaml
```

- At the moment, only Bitwarden is supported. Please raise an issue/PR for the support of any other secret manager tools.
- The secret stored in the secret manager tools must be the content of the file you're trying to protect in base64 encoded form.
- We then parse the file, fetch the secret from Bitwarden based on the value of the ID and replace that secret at the value of path.

Notice: In the Bitwarden you should pre-create vault items with secrets manually. You can do that using web user interface or cli: [bw create item](https://bitwarden.com/help/cli/#create). Secret value should be stored in the "password" field of the vault item (and encoded in the base64 like mentioned above). Also You can use command `bw list items` to retrieve detailed json with id information. But this command returns cached results for the login session. To get actual information,
you should make re-login: `bw logout` and `bw login` and then execute `bw list items`.

Please check [sre examples](operator/docs/sre/examples) directory for more details.
