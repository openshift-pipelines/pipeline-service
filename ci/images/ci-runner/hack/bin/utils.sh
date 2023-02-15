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
