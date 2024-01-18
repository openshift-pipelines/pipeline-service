#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=developer/openshift/utils.sh
source "$DEV_DIR/utils.sh"

setup_work_dir() {
  manifests_dir="$WORK_DIR/environment/compute/"

  echo "- Setup working directory:"
  mkdir -p "$manifests_dir"
  rsync --archive --delete "$DEV_DIR/gitops/local/" "$manifests_dir"

  configure_argocd_apps | indent
  setup_tekton_results | indent
}

configure_argocd_apps(){
  echo -n "- Updating source repository to '${GIT_URL}/tree/$GIT_REF': "
  # Patch the url/branch to target the expected repository/branch
  yq --inplace ".resources[1] = \"$GIT_URL/developer/openshift/gitops/argocd?ref=$GIT_REF\"" "$manifests_dir/kustomization.yaml"
  yq ".patches[] | .path" "$manifests_dir/kustomization.yaml" | while read -r patch; do
    yq --inplace ".spec.source.repoURL = \"$GIT_URL\", .spec.source.targetRevision = \"$GIT_REF\"" "$manifests_dir/$patch"
  done
  echo "OK"
}

setup_tekton_results() {
  echo -n "- Tekton Results: "
  get_tekton_results_credentials
  generate_tekton_results_db_ssl_cert
  patch_tekton_results_manifests
  echo "OK"
}

get_tekton_results_credentials() {
  tekton_results_credentials="$WORK_DIR/credentials/tekton-results/credentials.yaml"
  mkdir -p "$(dirname "$tekton_results_credentials")"
  if [ ! -e "$tekton_results_credentials" ]; then
    TEKTON_RESULTS_DATABASE_USER="$(yq '.tekton_results_db.user // "tekton"' "$CONFIG")"
    TEKTON_RESULTS_DATABASE_PASSWORD="$(yq ".tekton_results_db.password // \"$(openssl rand -base64 20)\"" "$CONFIG")"
    TEKTON_RESULTS_S3_USER="$(yq '.tekton_results_s3.user // "minio"' "$CONFIG")"
    TEKTON_RESULTS_S3_PASSWORD="$(yq ".tekton_results_s3.password // \"$(openssl rand -base64 20)\"" "$CONFIG")"
    cat << EOF > "$tekton_results_credentials"
---
db_password: $TEKTON_RESULTS_DATABASE_PASSWORD
db_user: $TEKTON_RESULTS_DATABASE_USER
s3_password: $TEKTON_RESULTS_S3_PASSWORD
s3_user: $TEKTON_RESULTS_S3_USER
EOF
  fi
  TEKTON_RESULTS_DATABASE_USER="$(yq ".db_user" "$tekton_results_credentials")"
  TEKTON_RESULTS_DATABASE_PASSWORD="$(yq ".db_password" "$tekton_results_credentials")"
  TEKTON_RESULTS_S3_USER="$(yq ".s3_user" "$tekton_results_credentials")"
  TEKTON_RESULTS_S3_PASSWORD="$(yq ".s3_password" "$tekton_results_credentials")"
}

generate_tekton_results_db_ssl_cert(){
  TEKTON_RESULTS_DB_SSL="$WORK_DIR/certificates/tekton-results"
  mkdir -p "$TEKTON_RESULTS_DB_SSL"
  openssl req -newkey rsa:4096 -nodes -text \
    -keyout "$TEKTON_RESULTS_DB_SSL/root.key" \
    -out "$TEKTON_RESULTS_DB_SSL/root.csr" \
    -subj "/CN=postgres-postgresql.tekton-results.svc.cluster.local" \
    -addext "subjectAltName=DNS:postgres-postgresql.tekton-results.svc.cluster.local" \
    > /dev/null 2>&1
  chmod og-rwx "$TEKTON_RESULTS_DB_SSL/root.key"
  openssl x509 -req -days 7 -text \
    -signkey "$TEKTON_RESULTS_DB_SSL/root.key" \
    -in "$TEKTON_RESULTS_DB_SSL/root.csr" \
    -extfile "/etc/ssl/openssl.cnf" \
    -extensions v3_ca \
    -out "$TEKTON_RESULTS_DB_SSL/ca.crt" \
    > /dev/null 2>&1
  openssl req -new -nodes -text \
    -out "$TEKTON_RESULTS_DB_SSL/root.csr" \
    -keyout "$TEKTON_RESULTS_DB_SSL/tls.key" \
    -subj "/CN=postgres-postgresql.tekton-results.svc.cluster.local" \
    -addext "subjectAltName=DNS:postgres-postgresql.tekton-results.svc.cluster.local" \
    > /dev/null 2>&1
  chmod og-rwx "$TEKTON_RESULTS_DB_SSL/tls.key"
  openssl x509 -req -text -days 7 -CAcreateserial \
    -in "$TEKTON_RESULTS_DB_SSL/root.csr" \
    -CA "$TEKTON_RESULTS_DB_SSL/ca.crt" \
    -CAkey "$TEKTON_RESULTS_DB_SSL/root.key" \
    -out "$TEKTON_RESULTS_DB_SSL/tls.crt" \
    > /dev/null 2>&1
}

patch_tekton_results_manifests(){
  yq --inplace "
    .data.[\"db.password\"]=\"$(echo -n "$TEKTON_RESULTS_DATABASE_PASSWORD" | base64)\",
    .data.[\"db.user\"]=\"$(echo -n "$TEKTON_RESULTS_DATABASE_USER" | base64)\"
  " "$WORK_DIR/environment/compute/tekton-results/tekton-results-db-secret.yaml"
  yq --inplace "
    .data.aws_access_key_id=\"$(echo -n "$TEKTON_RESULTS_S3_USER" | base64)\",
    .data.aws_secret_access_key=\"$(echo -n "$TEKTON_RESULTS_S3_PASSWORD" | base64)\"
  " "$WORK_DIR/environment/compute/tekton-results/tekton-results-s3-secret.yaml"
  string_data="$(cat <<EOF | base64
export MINIO_ROOT_USER="$TEKTON_RESULTS_S3_USER"
export MINIO_ROOT_PASSWORD="$TEKTON_RESULTS_S3_PASSWORD"
export MINIO_STORAGE_CLASS_STANDARD="EC:2"
export MINIO_BROWSER="on"
EOF
  )"
  yq --inplace "
    .data.[\"config.env\"]=\"$string_data\"
  " "$WORK_DIR/environment/compute/tekton-results/tekton-results-minio-config.yaml"
  yq --inplace "
    .data.[\"ca.crt\"]=\"$(base64 "$TEKTON_RESULTS_DB_SSL/ca.crt")\" |
    .data.[\"tls.crt\"]=\"$(base64 "$TEKTON_RESULTS_DB_SSL/tls.crt")\" |
    .data.[\"tls.key\"]=\"$(base64 "$TEKTON_RESULTS_DB_SSL/tls.key")\"
  " "$WORK_DIR/environment/compute/tekton-results/tekton-results-postgresql-tls-secret.yaml"
  yq --inplace "
  .data.[\"tekton-results-db-ca.pem\"]=\"$(cat "$TEKTON_RESULTS_DB_SSL/tls.crt" "$TEKTON_RESULTS_DB_SSL/ca.crt")\"
  " "$WORK_DIR/environment/compute/tekton-results/rds-db-cert-configmap.yaml"
}



deploy_application() {
  echo "- Deploy application:"

  echo "  - Apply configuration:"
  kubectl apply -k "$WORK_DIR/environment/compute" | indent 4

  echo "  - Check application status:"
  check_applications "openshift-gitops" "pipeline-service" | indent 4

  echo "  - Check subscription status:"
  check_subscriptions "openshift-operators" "openshift-pipelines-operator" | indent 4

  #checking if the pipelines and triggers pods are up and running
  echo "  - Check deployment status:"
  tektonDeployments=("tekton-pipelines-controller" "tekton-triggers-controller" "tekton-triggers-core-interceptors" "tekton-chains-controller")
  check_deployments "openshift-pipelines" "${tektonDeployments[@]}" | indent 4
  resultsDeployments=("tekton-results-api" "tekton-results-watcher")
  check_deployments "tekton-results" "${resultsDeployments[@]}" | indent 4
  resultsStatefulsets=("postgres-postgresql" "storage-pool-0")
  check_statefulsets "tekton-results" "${resultsStatefulsets[@]}" | indent 4

  echo "  - Check pods status for controlplane namespaces:"
  # list of control plane namespaces
  CONTROL_PLANE_NS=("openshift-apiserver" "openshift-controller-manager" "openshift-etcd" "openshift-ingress" "openshift-kube-apiserver" "openshift-kube-controller-manager" "openshift-kube-scheduler")
  for ns in "${CONTROL_PLANE_NS[@]}"; do
    check_crashlooping_pods "$ns" | indent 4
  done
}

main() {
  if [ -n "${DEBUG:-}" ]; then
    set -x
  fi
  setup_work_dir
  deploy_application
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
