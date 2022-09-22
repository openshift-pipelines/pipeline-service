# Development Environment in a Container

This folder holds the configuration to build and run an image embedding all the required
dependencies to work on the project.

## Using the image
You can start a container with `./run.sh`, by default it will use the latest image available on `quay.io`.
If you want to build a local image (e.g. after changing dependencies locally), you can use the `--dev` flag.

When exiting the container, it will be stopped. Running `./run.sh` will restart the container.
This allow users to preserve any customization they might have done.

## Managing containers
One container will be spawned per repository clone, and you'll see that the container name is based on the clone path.

## Integration with IDEs
This image is used as the base image by the IDE integration (e.g. `.devcontainer` for VS Code).
