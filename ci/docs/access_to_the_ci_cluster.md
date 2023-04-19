# Access to the CI cluster

Developers might require access to the CI cluster to troubleshoot failing PipelineRuns.

The process to grant them access is:
* Add them as a member to [appstudio-pipeline-sre](https://github.com/orgs/rhd-ci-cd-sre/teams/appstudio-pipeline-sre/members).
* Have them log to the [cluster](https://console-openshift-console.apps.pipeline-stage.3jhu.p1.openshiftapps.com/dashboards). This will create their [user](https://console-openshift-console.apps.pipeline-stage.3jhu.p1.openshiftapps.com/k8s/cluster/user.openshift.io~v1~User).
* On the cluster, add the user to the [plnsvc group](https://console-openshift-console.apps.pipeline-stage.3jhu.p1.openshiftapps.com/k8s/cluster/user.openshift.io~v1~Group/plnsvc).
