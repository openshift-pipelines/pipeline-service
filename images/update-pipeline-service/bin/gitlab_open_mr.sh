#!/usr/bin/env bash

raise_mr_gitlab() {
  SOURCE_BRANCH="robot/pipeline-service-update"
  GITLAB_TOKEN="${GITLAB_TOKEN}"
  current_commit=$1
  latest_commit=$2
  if [[ "$current_commit" == "$latest_commit" ]]; then
    printf "Latest images already available\n"
    exit 0
  fi
  printf "Replacing the image tags with the latest commit sha and raising a MR\n"
  sed -i "s/$current_commit/$latest_commit/g" ".gitlab-ci.yml"

  for i in {1..3}; do
    resp_http_code=$(curl -k -w '%{http_code}' -o /tmp/commit_logs.json -X PUT --header "PRIVATE-TOKEN: $GITLAB_TOKEN" --header "Content-Type: application/json" --data '{"branch": "robot/pipeline-service-update", "commit_message": "Updating the image tag with the latest commit SHA", "content": '"$(jq -Rs '.' .gitlab-ci.yml)"'}' "https://gitlab.cee.redhat.com/api/v4/projects/$CI_PROJECT_ID/repository/files/.gitlab-ci.yml")
    printf "%s\n" "$resp_http_code"
    cat /tmp/commit_logs.json

    if [[ "$resp_http_code" == "200" ]]; then
      # raise a MR
      BODY_MR="{
          \"id\": \"${CI_PROJECT_ID}\",
          \"source_branch\": \"${SOURCE_BRANCH}\",
          \"target_branch\": \"main\",
          \"title\": \"Update image tags with the latest commit\"
      }";

      printf "Check if a MR already exists\n"
      existing_mr=$(curl -sk \
      -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      "https://gitlab.cee.redhat.com/api/v4/projects/$CI_PROJECT_ID/merge_requests?source_branch=$SOURCE_BRANCH&state=opened")

      if [  "$(echo "$existing_mr" | jq '. | length')" == 0 ]; then
        printf "Raising a new MR\n"
        resp_http_code=$(curl -k -w '%{http_code}' -o /tmp/raise_pr.json \
            -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            -H "Content-Type: application/json" \
            --data-raw "${BODY_MR}" \
            -X POST "https://gitlab.cee.redhat.com/api/v4/projects/$CI_PROJECT_ID/merge_requests")
        if [[ "$resp_http_code" == "201" ]]; then
          printf "MR successfully raised\n"
          exit 0
        else
          printf "Unable to raise a new MR\n" >&2
          exit 1
        fi
      else
        printf "MR already exists. Pushed the latest tag to the same MR.\n"
        exit 0
      fi
    return
    else
      if [[ "$i" -lt 3 ]]; then
        printf "Unable to commit the file. Retrying...\n"
        sleep 5
      else
        printf "Error while committing the file. Status code: %s\n" "${resp_http_code}" >&2
        exit 1
      fi
    fi
  done
}