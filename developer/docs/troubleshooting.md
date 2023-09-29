# Troubleshooting

## If we install yq via snap store on Fedora, it uses strict confinement policy which does not provide access to root (including /tmp).

```
$ yq e ".current-context" "/tmp/tmp.QNwtlzJzZh/credentials/kubeconfig/compute/compute.kubeconfig.base"
Error: open /tmp/tmp.QNwtlzJzZh/credentials/kubeconfig/compute/compute.kubeconfig.base: no such file or directory
```

Make sure tools such as yq, jq or any other that is using a strict confinement policy is setup to have access to root filesystem. This could be done by installing these tools locally rather than through package managers.
