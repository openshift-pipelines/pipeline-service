# Documentation for Developers

## Development environment

You can see the required dependencies in [DEPENDENCIES.md](../../DEPENDENCIES.md).

You have various options to setup your environment:
* local environment: the [install.sh](../images/devenv/install.sh) can be used to
install all dependencies but be careful as it will impact your system configuration by
installing/configuring packages locally.
* running in a container: use [run.sh](../images/devenv/run.sh) to spawn a container
and be dropped in a shell.
* VS Code in a container: you can use the `Remote Development` extension
(`ms-vscode-remote.vscode-remote-extensionpack`), and VS Code will use the content of
[.devcontainer](../../.devcontainer) to spawn a container and drop you in the development
environment. This will require an action on your side when opening the project, so look
out for the `Reopen in container` notification.

## PR process

* When you open a PR, add a few reviewers. If the PR solves a GitHub issue, make sure
  that the contributor who opened the issue is one of the reviewers.
* If you do not see any progress on the PR over a couple of days, feel free to put a
  comment tagging one or two users asking them to take the time to review your change.
* The reviewer will perform the code review. If they are satisfied with the change, and
  they feel like the change does not require a second pair of eyes, they will merge the
  PR.
* The PR may be large enough or import enough to require a second opinion. In that case,
  the 1st reviewer will put a comment asking for an additional review. In that case, the
  last reviewer to approve the PR is responsible for merging it.
