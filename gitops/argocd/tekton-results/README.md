# Tekton Results

## ***Description*** 
This will install tekton results on cluster to gather Tekton Pipelinerun results for long term storage.

Installation is based on the [installation instructions](https://github.com/tektoncd/results/blob/main/docs/install.md) from upstream tekton results

In a ckcp install, a postgresql database is installed so that results can be stored on cluster otherwise tekton results will use a configurable external database such as Amazon's RDS. 

More information can be found [here](https://github.com/tektoncd/results#readme)