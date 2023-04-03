#!/usr/bin/env bash

# turns off tracing even with set -x mode enabled across the script to prevent secrets leaking
setx_off() {
    set +x
}

# turns on tracing
setx_on() {
    set -x
}

indent () {
    sed "s/^/$(printf "%$1s")/"
}

open_bitwarden_session() {
    setx_off
    BW_CLIENTID="${BW_CLIENTID:-}"
    BW_CLIENTSECRET="${BW_CLIENTSECRET:-}"
    BW_PASSWORD="${BW_PASSWORD:-}"
  
    if [ -z "$BW_CLIENTID" ]; then
        printf "Error: BW_CLIENTID is unset.\n" >&2 | indent 2
        exit 1
    fi
    if [ -z "$BW_PASSWORD" ]; then
        printf "Error: BW_PASSWORD is unset.\n" >&2 | indent 2
        exit 1
    fi
    setx_on
  
    printf "bitwarden credentials: OK\n" | indent 2
    if [ "$(bw logout >/dev/null 2>&1)$?" -eq 0 ]; then
      printf "Logout successful.\n" >/dev/null
    fi
    if (setx_off; BW_CLIENTID="$BW_CLIENTID" BW_CLIENTSECRET="$BW_CLIENTSECRET" bw login --apikey >/dev/null 2>&1); then
      printf "Login successful.\n" >/dev/null
    fi
  
    login_status=$(bw login --check 2>&1)
    if [ "$login_status" = "You are not logged in." ]; then
      printf "Error while logging into Bitwarden.\n" >&2 | indent 2
      return
    fi
  
    printf "Fetch secrets from bitwarden server\n" | indent 2
    setx_off
    session=$(BW_PASSWORD="$BW_PASSWORD" bw unlock --passwordenv BW_PASSWORD --raw)
    setx_on
}

get_password() {
    setx_off
    local itemid="$1"
    password=$(bw get password "$itemid" --session "$session")
    export password
    setx_on
}

get_attachment() {
    setx_off
    local itemid="$1"
    local output="$2"
    bw get attachment credentials --itemid "$itemid" --session "$session" --output "$output"
    setx_on
}

export PULL_SECRET=$HOME/pull-secret

export AWS_CREDENTIALS=$HOME/.aws/credentials

get_aws_credentials() {
    get_attachment "7025d81b-2788-4416-9fe1-afa300dcf0b4" "$AWS_CREDENTIALS"
}

get_base_domain() {
    get_password "7ea65e94-1865-410b-ab8e-af90006682d7"
    setx_off
    BASE_DOMAIN="${password}"
    export BASE_DOMAIN
    setx_on
}

get_pull_secret() {
    get_password "97960272-52cd-43bd-a1df-af8d003b4efb" 
    cat <<< "${password}" | base64 -d > "$PULL_SECRET"
}

get_github_user() {
    get_password "49988640-d47c-4cac-861e-afaa00721e18"
    setx_off
    GITHUB_USER="${password}"
    export GITHUB_USER
    setx_on
}

get_github_token() {
    get_password "5c9597fb-083c-4321-9452-afaa00760c99"
    setx_off
    GITHUB_TOKEN="${password}"
    export GITHUB_TOKEN
    setx_on
}

get_quay_token() {
    get_password "50c61ee9-82ad-4316-95fd-afaa0076a17d"
    setx_off
    QUAY_TOKEN="${password}"
    export QUAY_TOKEN
    setx_on
}

get_quay_oauth_user() {
    get_password "fee70791-4bdc-4ddf-bd78-afaa0076fb6a"
    setx_off
    QUAY_OAUTH_USER="${password}"
    export QUAY_OAUTH_USER
    setx_on
}

get_quay_oauth_token() {
    get_password "7c494bb5-75ec-4b80-8085-afaa00774d83"
    setx_off
    QUAY_OAUTH_TOKEN="${password}"
    export QUAY_OAUTH_TOKEN
    setx_on
}

get_quay_oauth_token_release_source() {
    get_password "28b147c0-2988-4d7d-b359-afaa0077e626"
    setx_off
    QUAY_OAUTH_TOKEN_RELEASE_SOURCE="${password}"
    export QUAY_OAUTH_TOKEN_RELEASE_SOURCE
    setx_on
}

get_quay_oauth_token_release_destination() {
    get_password "0e8b59e3-6ac2-47d6-98a4-afaa00782b9c"
    setx_off
    QUAY_OAUTH_TOKEN_RELEASE_DESTINATION="${password}"
    export QUAY_OAUTH_TOKEN_RELEASE_DESTINATION
    setx_on
}

get_github_accounts() {
    get_password "bb32321b-601c-4c92-8605-afc40050d9e4"
    setx_off
    IFS=',' read -r -a GITHUB_ACCOUNTS_ARRAY <<< "${password}" 
    export GITHUB_ACCOUNTS_ARRAY
    setx_on
}

get_default_quay_org_token() {
    get_password "8376d3eb-9b89-4420-b49d-afd9009db07b"
    setx_off
    DEFAULT_QUAY_ORG_TOKEN="${password}"
    export DEFAULT_QUAY_ORG_TOKEN
    setx_on
}