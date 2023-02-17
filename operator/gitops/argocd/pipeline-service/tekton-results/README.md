# Tekton Results

Tekton Results aims to help users logically group CI/CD workload history and separate out long term result storage away from the Pipeline controller. This allows you to:

- Provide custom Result Metadata about your CI/CD workflows that aren't available in the Tekton TaskRun and PipelineRun CRDs (such as post-run actions).
- Group related workloads together (e.g., bundle related TaskRuns and PipelineRuns into a single unit).
- Separate long-term result history from the Pipeline CRD controller, freeing up etcd resources for Run execution.

## Description

This will install Tekton results on the cluster to gather Tekton PipelineRun and TaskRun results (status and logs) for long term storage.
Installation is based on the [installation instructions](https://github.com/tektoncd/results/blob/main/docs/install.md) from upstream Tekton results. The image is built using the [downstream](https://github.com/openshift-pipelines/tektoncd-results) fork of Tekton Results and stored in <https://quay.io/repository/redhat-appstudio/tekton-results-api> and <https://quay.io/repository/redhat-appstudio/tekton-results-watcher>, and referenced using the latest commit hash on the downstream repo.
In a [dev environment](../../../../developer/README.md), a PostgreSQL database is installed so that results can be stored on the cluster. Otherwise, Tekton results will use a configurable external database, such as Amazon's RDS.
More information can be found [here](https://github.com/tektoncd/results#readme)
