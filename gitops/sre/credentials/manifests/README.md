# Confidential manifests

This directory and subdirectories' purpose is to contain the manifests with confidential information required to setup the service.

One such example is the `signing-secrets` secret required by tekton-chains during signing and which must be shared across all clusters.

---
**_NOTES:_**

The information contained in the manifests files is confidential. Measures should be taken to protect it from being disclosed. This directory and sub-directories should not contain these files in a public repository. Don't forget to amend the `.gitignore` file if you want to add other files to a private fork of this repository.

---
