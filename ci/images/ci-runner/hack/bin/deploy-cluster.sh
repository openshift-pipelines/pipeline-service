#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

# shellcheck source=ci/images/ci-runner/hack/bin/utils.sh
source "$SCRIPT_DIR/utils.sh"

print_debug_info() {
    printf "Print debug info......\n" | indent 2
    rosa --region "$REGION" describe cluster --cluster="$CLUSTER_NAME"
}

# Check all of clusteroperators are AVAILABLE
check_clusteroperators() {
    operators=$(kubectl get co -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}')

    for operator in $operators; do
        # need to check if the operator is available or not in a loop
        retries=0
        max_retries=10
        # if the operator is not available, wait 60s and check again
        while [ "$retries" -lt "$max_retries" ]; do
            available=$(kubectl get co "$operator" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
            if [ "$available" == "True" ]; then
                break
            fi
            sleep 60
            retries=$((retries + 1))
            echo "Retried $retries times..."
        done
        # if the operator is still not available after 10 times, exit 1
        if [ "$retries" -eq "$max_retries" ]; then
            echo "Operator $operator is not available" >&2
            # print the status of all cluster operators 
            kubectl get co
            # print the status of the failed cluster operator
            kubectl get co "$operator" -o yaml
            exit 1
        fi
    done

    echo "All operators are available"
}

deploy_cluster() {
    printf "Log in to your Red Hat account...\n" | indent 2
    setx_off
    rosa login --token="$ROSA_TOKEN"
    setx_on

    printf "Provision ROSA with HCP cluster...\n" | indent 2
    rosa create cluster --cluster-name "$CLUSTER_NAME" \
        --sts --mode=auto --oidc-config-id "24132snjs8gktc5rtufqv8hggjv3ivbt" \
        --operator-roles-prefix plnsvc-ci --region "$REGION" --version "$OCP_VERSION" \
        --compute-machine-type m5.2xlarge \
        --subnet-ids="subnet-001487732ebdd14f4,subnet-0718fb663f4b97f38,subnet-0fe426997da62662c" \
        --hosted-cp -y

    printf "Track the progress of the cluster creation...\n" | indent 2
    rosa logs install --cluster="$CLUSTER_NAME" --region "$REGION" --watch

    printf "ROSA with HCP cluster is ready, create a cluster admin account for accessing the cluster\n" | indent 2
    admin_output="$(rosa create admin --region "$REGION" --cluster="$CLUSTER_NAME")"
 
    # Get the admin account credentials and API server URL
    admin_user="$(echo "$admin_output" | grep -oP '(?<=--username ).*(?= --password)')"
    admin_pass="$(echo "$admin_output" | grep -oP '(?<=--password ).*')"
    api_url="$(echo "$admin_output" | grep -oP '(?<=oc login ).*(?= --username)')"

    # Use the admin account to login to the cluster in a loop until the account is active.
    max_retries=5
    retries=0
    export KUBECONFIG="$KUBECONFIG_DIR/kubeconfig"
    while ! oc login "$api_url" --username "$admin_user" --password "$admin_pass" > /dev/null 2>&1; do
        if [ "$retries" -eq "$max_retries" ]; then
            echo "[ERROR] Failed to login the cluster." >&2
            print_debug_info
            exit 1
        fi
        sleep 60
        retries=$((retries + 1))
        echo "Retried $retries times..."
    done

    printf "The following is the cluster kubeconfig:\n" | indent 2
    cat "$KUBECONFIG"

    #Workaround: Check if apiserver is ready by calling kubectl get nodes
    if ! timeout 300s bash -c "while ! kubectl get nodes >/dev/null 2>/dev/null; do printf '.'; sleep 10; done"; then
        echo "API server is not ready" >&2
        exit 1
    fi
    check_clusteroperators
}

deploy_cluster