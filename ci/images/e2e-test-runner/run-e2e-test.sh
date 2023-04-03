#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

PROJECT_DIR="$(
  cd "$SCRIPT_DIR/../../.." >/dev/null || exit 1
  pwd
)"

# shellcheck source=ci/images/ci-runner/hack/bin/utils.sh
source "$PROJECT_DIR/ci/images/ci-runner/hack/bin/utils.sh"

export_variables() {
  printf "Export variables\n" | indent 2
  # The following variables are exported by the Stonesoup CI:
  # DEFAULT_QUAY_ORG DEFAULT_QUAY_ORG_TOKEN GITHUB_USER GITHUB_TOKEN QUAY_TOKEN QUAY_OAUTH_USER QUAY_OAUTH_TOKEN QUAY_OAUTH_TOKEN_RELEASE_SOURCE QUAY_OAUTH_TOKEN_RELEASE_DESTINATION 
  # GITHUB_ACCOUNTS_ARRAY PREVIOUS_RATE_REMAINING GITHUB_USERNAME_ARRAY GH_RATE_REMAINING

  export DEFAULT_QUAY_ORG=redhat-appstudio-qe
  printf "Fetch secrets from bitwarden server\n" | indent 2

  open_bitwarden_session
  get_default_quay_org_token
  get_github_user
  get_github_token
  get_quay_token
  get_quay_oauth_user
  get_quay_oauth_token
  get_quay_oauth_token_release_source
  get_quay_oauth_token_release_destination
  get_github_accounts
}

handle_ratelimit() {
  PREVIOUS_RATE_REMAINING=0

  # user stored: username:token,username:token
  for account in "${GITHUB_ACCOUNTS_ARRAY[@]}"
  do :
      IFS=':' read -r -a GITHUB_USERNAME_ARRAY <<< "$account"

      GH_RATE_REMAINING=$(curl -s \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_USERNAME_ARRAY[1]}"\
      https://api.github.com/rate_limit | jq ".rate.remaining")

      echo -e "[INFO ] user: ${GITHUB_USERNAME_ARRAY[0]} with rate limit remaining $GH_RATE_REMAINING"
      if [[ "${GH_RATE_REMAINING}" -ge "${PREVIOUS_RATE_REMAINING}" ]];then
          GITHUB_USER="${GITHUB_USERNAME_ARRAY[0]}"
          GITHUB_TOKEN="${GITHUB_USERNAME_ARRAY[1]}"
      fi
      PREVIOUS_RATE_REMAINING="${GH_RATE_REMAINING}"
  done

  echo -e "[INFO] Start tests with user: ${GITHUB_USER}"
}

run_test() {
  ##git config
  git config --global user.name "redhat-appstudio-qe-bot"
  git config --global user.email redhat-appstudio-qe-bot@redhat.com

  mkdir -p "${HOME}/creds"
  GIT_CREDS_PATH="${HOME}/creds/file"
  git config --global credential.helper "store --file ${GIT_CREDS_PATH}"
  echo "https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com" > "${GIT_CREDS_PATH}"


  cd "$(mktemp -d)"

  git clone --branch main "https://${GITHUB_TOKEN}@github.com/redhat-appstudio/e2e-tests.git" .
  ## Deploy StoneSoup
  make local/cluster/prepare

  # Launch partial StoneSoup e2e tests
  go mod tidy
  go mod vendor
  make build
  ./bin/e2e-appstudio --ginkgo.label-filter "pipeline" --ginkgo.vv
}



export_variables
handle_ratelimit
run_test