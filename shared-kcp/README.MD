

##Add a workload cluster to kcp shared instance
###Summary
This script automates adding a workload cluster to kcp shared instance.
Instructions are taken from the kcp onboarding doc.

###Assumptions and Defaults

- Script assumes the workload cluster to be added is at _$HOME/.kube/config_ and assigns this to KUBECONFIG variable. You can always provide a different KUBECONFIG path.

- _sharedkcp.kubeconfig_ contains the org ID of **_pipelines-service_** team and hence other members of pipelines-service team can use this file as is. Other teams need to replace the org ID with theirs.

- You can modify the contents of the yaml resources in order to change the names of namespace, sa, workloadcluster etc.