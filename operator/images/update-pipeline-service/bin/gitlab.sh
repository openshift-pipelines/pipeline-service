#!/usr/bin/env bash

get_current_commit() {
  CURRENT_COMMIT=$(yq '.deploy-job.image.name' <"$GITLAB_CI_PATH" | cut -d ':' -f2)

  if [[ "$CURRENT_COMMIT" == "$LATEST_COMMIT" ]]; then
    printf "Already using the latest tag: '%s'\n" "$LATEST_COMMIT"
    exit 0
  fi
  COMMIT_MESSAGE="Updating images tag from '$CURRENT_COMMIT' to '$LATEST_COMMIT'"
}

update_local_repository() {
  printf "Replacing the images tag with the latest commit sha\n"
  sed -i "s/$CURRENT_COMMIT/$LATEST_COMMIT/g" "$GITLAB_CI_PATH"
}

get_mr_id() {
  merge_request_iid=$(curl -sk \
    -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$GITLAB_PROJECT_URL/merge_requests?source_branch=$SOURCE_BRANCH&state=opened" | yq ".[0].iid")
}

cancel_merge_when_pipeline_succeeds() {
  printf "Cancel automerge\n"
  http_url="$GITLAB_PROJECT_URL/merge_requests/$merge_request_iid/cancel_merge_when_pipeline_succeeds"
  http_logs="/tmp/cancel_merge_when_pipeline_succeeds.json"
  retry=3
  while true; do
    resp_http_code=$(curl -k -w '%{http_code}' -o "$http_logs" \
      -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      -X POST "$http_url")
    case $resp_http_code in
    2*)
      break
      ;;
    406)
      # The merge request is not set to be merged when the pipeline succeeds.
      # c.f. https://docs.gitlab.com/ee/api/merge_requests.html#cancel-merge-when-pipeline-succeeds
      break
      ;;
    *)
      http_retry
      ;;
    esac
  done
}

push_changes() {
  printf "Pushing the changes to GitLab\n"

  # Create the branch
  http_url="$GITLAB_PROJECT_URL/repository/branches?branch=${SOURCE_BRANCH}&ref=main"
  http_logs="/tmp/create_branch.json"
  retry=3
  while true; do
    resp_http_code=$(
      curl -k -w '%{http_code}' -o "$http_logs" \
        -X POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --silent \
        "$http_url"
    )
    case $resp_http_code in
    2*)
      break
      ;;
    400)
      if grep -q "Branch already exists" "$http_logs"; then
        break
      fi
      http_retry
      ;;
    *)
      http_retry
      ;;
    esac
  done

  # Push the change onto the branch
  http_url="$GITLAB_PROJECT_URL/repository/files/$GITLAB_CI_PATH"
  http_logs="/tmp/push_to_repository.json"
  retry=3
  while true; do
    resp_http_code=$(
      curl -k -w '%{http_code}' -o "$http_logs" \
        -X PUT \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data '{
            "branch": "robot/pipeline-service-update",
            "commit_message": "'"$COMMIT_MESSAGE"'",
            "content": '"$(jq -Rs '.' "$GITLAB_CI_PATH")"'
          }' \
        --silent \
        "$http_url"
    )
    case $resp_http_code in
    2*)
      break
      ;;
    *)
      http_retry
      ;;
    esac
  done
}

open_merge_request() {
  printf "Open merge request\n"
  merge_request_body="{
    \"id\": \"${CI_PROJECT_ID}\",
    \"source_branch\": \"${SOURCE_BRANCH}\",
    \"target_branch\": \"main\",
    \"title\": \"${COMMIT_MESSAGE}\"
  }"
  http_url="$GITLAB_PROJECT_URL/merge_requests"
  http_logs="/tmp/open_merge_request.json"
  retry=3
  while true; do
    resp_http_code=$(
      curl -k -w '%{http_code}' -o "$http_logs" \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        -H "Content-Type: application/json" \
        --data-raw "${merge_request_body}" \
        -X POST "$http_url"
    )
    case $resp_http_code in
    2*)
      break
      ;;
    *)
      http_retry
      ;;
    esac
  done
}

merge_when_pipeline_succeeds() {
  printf "Enabling automerge\n"
  merge_body='{
    "merge_when_pipeline_succeeds": true,
    "should_remove_source_branch": true,
    "squash": true,
    "squash_commit_message": "'"$COMMIT_MESSAGE"'"
}'
  http_url="$GITLAB_PROJECT_URL/merge_requests/$merge_request_iid/merge"
  http_logs="/tmp/merge.json"
  retry=3
  while true; do
    resp_http_code=$(curl -k -w '%{http_code}' -o "$http_logs" \
      --silent \
      -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      -H "Content-Type: application/json" \
      --data-raw "${merge_body}" \
      -X PUT "$http_url")
    case $resp_http_code in
    2*)
      break
      ;;
    405)
      # The merge request is not able to be merged.
      # c.f. https://docs.gitlab.com/ee/api/merge_requests.html#merge-a-merge-request
      merge_body=$(echo "$merge_body" | grep -v "merge_when_pipeline_succeeds")
      http_retry
      ;;
    *)
      http_retry
      ;;
    esac
  done
}

gitlab_process() {
  # GitLab variables to be set in 'Settings'-'CI/CD'-'Variables'
  GITLAB_TOKEN=${GITLAB_TOKEN:-}
  if [ -z "$GITLAB_TOKEN" ]; then
    printf "Unset environment variable: \$GITLAB_TOKEN\n" >&2
    exit 1
  fi

  GITLAB_PROJECT_URL="$CI_API_V4_URL/projects/$CI_PROJECT_ID"
  SOURCE_BRANCH="robot/pipeline-service-update"
  GITLAB_CI_PATH=".gitlab-ci.yml"

  # Make shellcheck happy
  retry=${retry:-}

  # main
  get_latest_commit
  get_current_commit
  update_local_repository
  get_mr_id
  if [ "$merge_request_iid" != "null" ]; then
    cancel_merge_when_pipeline_succeeds
  fi
  push_changes
  if [ "$merge_request_iid" = "null" ]; then
    open_merge_request
  else
    printf "Merge request already exists with iid '%s'\n" "$merge_request_iid"
  fi
  if [ "$AUTOMERGE" = "true" ]; then
    merge_when_pipeline_succeeds
  else
    printf "Merge request will not be automerged.\n"
  fi
  exit 0
}
