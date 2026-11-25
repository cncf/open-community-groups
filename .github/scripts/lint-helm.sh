#!/usr/bin/env bash
set -euo pipefail

CHART_DIR="charts/ocg"
VALUES_FILE=".github/scripts/helm-ci-values.yaml"
RELEASE_NAME="ocg"
NAMESPACE="default"
TEST_CA_CERT=$'-----BEGIN CERTIFICATE-----\nCI-TEST-CERT\n-----END CERTIFICATE-----'

for cmd in helm yq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required tool '$cmd' not found in PATH" >&2
    exit 1
  fi
done

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

full_feature_args=(
  --set postgresql.enabled=false
  --set db.host=db.example.com
  --set db.sslMode=require
  --set db.tls.mode=verify-full
  --set-string "db.tls.caCert=${TEST_CA_CERT}"
  --set dynamicResourceNamePrefixEnabled=true
  --set redirector.enabled=true
  --set redirector.ingress.enabled=true
  --set images.provider=s3
  --set images.s3.bucket=ci-test-bucket
  --set images.s3.region=us-east-1
  --set images.s3.connectTimeoutSecs=15
  --set images.s3.requestTimeoutSecs=45
  --set meetings.zoom.enabled=true
  --set payments.enabled=true
  --set externalPayments.enabled=true
  --set 'externalPayments.allowedCountries={US}'
  --set server.rateLimit.enabled=true
  --set server.rateLimit.clientIp.source=header
  --set 'server.redirectHosts={alt.example.com}'
  --set server.security.cspReportOnly=true
  --set server.security.cspReportUri=https://reports.example.com/csp
)

assert_eq() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [ "$actual" != "$expected" ]; then
    echo "assertion failed ($label): expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

render_and_validate() {
  local case_name="$1"
  local mode="$2"
  local db_mode="$3"
  local prefix="$4"
  local expect_redirector="$5"
  shift 5

  local out="$tmp_dir/${case_name}.yaml"
  local extra_flags=()
  if [ "$mode" = "upgrade" ]; then
    extra_flags+=(--is-upgrade)
  fi

  echo "- Rendering $case_name.."
  helm template "$RELEASE_NAME" "$CHART_DIR" \
    --namespace "$NAMESPACE" \
    -f "$VALUES_FILE" \
    ${extra_flags[@]+"${extra_flags[@]}"} \
    "$@" >"$out"

  # Ensure every rendered Kubernetes manifest is valid YAML.
  yq eval '.' "$out" >/dev/null

  # Verify embedded server.yml parses as valid YAML and targets the expected DB host.
  local server_yml="$tmp_dir/${case_name}-server.yml"
  yq -r "select(.kind == \"Secret\" and .metadata.name == \"${prefix}server-config\") | .stringData[\"server.yml\"]" "$out" >"$server_yml"
  yq eval '.' "$server_yml" >/dev/null
  local expected_db_host
  if [ "$db_mode" = "bundled" ]; then
    expected_db_host="${RELEASE_NAME}-postgresql.${NAMESPACE}"
  else
    expected_db_host="db.example.com"
  fi
  assert_eq "$case_name server.yml db.host" "$(yq -r '.db.host' "$server_yml")" "$expected_db_host"

  # Verify security header defaults vs explicit full-feature overrides.
  if [ "$expect_redirector" = "true" ]; then
    assert_eq "$case_name server.yml server.security.csp_report_only" "$(yq -r '.server.security.csp_report_only' "$server_yml")" "true"
    assert_eq "$case_name server.yml server.security.csp_report_uri" "$(yq -r '.server.security.csp_report_uri' "$server_yml")" "https://reports.example.com/csp"
  else
    assert_eq "$case_name server.yml server.security.csp_report_only" "$(yq -r '.server.security.csp_report_only' "$server_yml")" "false"
    assert_eq "$case_name server.yml server.security.csp_report_uri" "$(yq -r '.server.security.csp_report_uri' "$server_yml")" "null"
  fi

  # Guard dbmigrator-config hook contract across both install and upgrade.
  local migrator_hook migrator_delete_policy
  migrator_hook=$(yq -r "select(.kind == \"Secret\" and .metadata.name == \"${prefix}dbmigrator-config\") | .metadata.annotations[\"helm.sh/hook\"]" "$out")
  migrator_delete_policy=$(yq -r "select(.kind == \"Secret\" and .metadata.name == \"${prefix}dbmigrator-config\") | .metadata.annotations[\"helm.sh/hook-delete-policy\"]" "$out")
  assert_eq "$case_name dbmigrator-config hook" "$migrator_hook" "pre-install,pre-upgrade"
  assert_eq "$case_name dbmigrator-config hook-delete-policy" "$migrator_delete_policy" "before-hook-creation"

  # Verify install vs upgrade Job and initContainer transitions.
  local job_names wait_init
  job_names=$(yq -r 'select(.kind == "Job") | .metadata.name' "$out" | tr '\n' ' ' | sed 's/ *$//')
  wait_init=$(yq -r "select(.kind == \"Deployment\" and .metadata.name == \"${prefix}server\") | .spec.template.spec.initContainers[] | select(.name == \"check-dbmigrator-run\") | .name" "$out")
  if [ "$mode" = "install" ]; then
    assert_eq "$case_name Job name" "$job_names" "${prefix}dbmigrator-install"
    local install_job_hook
    install_job_hook=$(yq -r "select(.kind == \"Job\" and .metadata.name == \"${prefix}dbmigrator-install\") | .metadata.annotations[\"helm.sh/hook\"] // \"\"" "$out")
    assert_eq "$case_name dbmigrator-install hook" "$install_job_hook" ""
    assert_eq "$case_name server check-dbmigrator-run" "$wait_init" "check-dbmigrator-run"
  else
    assert_eq "$case_name Job name" "$job_names" "${prefix}dbmigrator-upgrade"
    local upgrade_job_hook
    upgrade_job_hook=$(yq -r "select(.kind == \"Job\" and .metadata.name == \"${prefix}dbmigrator-upgrade\") | .metadata.annotations[\"helm.sh/hook\"]" "$out")
    assert_eq "$case_name dbmigrator-upgrade hook" "$upgrade_job_hook" "pre-upgrade"
    assert_eq "$case_name server check-dbmigrator-run" "$wait_init" ""
  fi

  # Verify bundled vs external PostgreSQL StatefulSet presence.
  local pg_statefulsets
  pg_statefulsets=$(yq -r 'select(.kind == "StatefulSet") | .metadata.name' "$out")
  if [ "$db_mode" = "bundled" ]; then
    assert_eq "$case_name postgresql StatefulSet" "$pg_statefulsets" "${RELEASE_NAME}-postgresql"
  else
    assert_eq "$case_name postgresql StatefulSet" "$pg_statefulsets" ""
  fi

  # Verify optional redirector manifests and multiline DB TLS CA rendering when enabled.
  if [ "$expect_redirector" = "true" ]; then
    local redirector_yml="$tmp_dir/${case_name}-redirector.yml"
    yq -r "select(.kind == \"Secret\" and .metadata.name == \"${prefix}redirector-config\") | .stringData[\"redirector.yml\"]" "$out" >"$redirector_yml"
    yq eval '.' "$redirector_yml" >/dev/null
    assert_eq "$case_name redirector.yml db.host" "$(yq -r '.db.host' "$redirector_yml")" "$expected_db_host"
    assert_eq "$case_name server.yml db.tls.ca_cert" "$(yq -r '.db.tls.ca_cert' "$server_yml")" "$TEST_CA_CERT"
    assert_eq "$case_name server.yml images.connect_timeout_secs" "$(yq -r '.images.connect_timeout_secs' "$server_yml")" "15"
    assert_eq "$case_name server.yml images.request_timeout_secs" "$(yq -r '.images.request_timeout_secs' "$server_yml")" "45"
    assert_eq "$case_name redirector.yml db.tls.ca_cert" "$(yq -r '.db.tls.ca_cert' "$redirector_yml")" "$TEST_CA_CERT"
    assert_eq "$case_name dbmigrator-config ca.crt" "$(yq -r "select(.kind == \"Secret\" and .metadata.name == \"${prefix}dbmigrator-config\") | .stringData[\"ca.crt\"]" "$out")" "$TEST_CA_CERT"
  fi
}

assert_template_fails() {
  local label="$1"
  local expected_substring="$2"
  shift 2

  echo "- Verifying negative check ($label).."
  local err_file="$tmp_dir/err.log"
  if helm template "$RELEASE_NAME" "$CHART_DIR" "$@" >/dev/null 2>"$err_file"; then
    echo "assertion failed ($label): expected helm template to fail, but it succeeded" >&2
    exit 1
  fi
  if ! grep -Fq "$expected_substring" "$err_file"; then
    echo "assertion failed ($label): expected error containing '$expected_substring', got:" >&2
    cat "$err_file" >&2
    exit 1
  fi
}

echo "==> Running helm lint checks"
helm lint --strict "$CHART_DIR" -f "$VALUES_FILE"
helm lint --strict "$CHART_DIR" -f "$VALUES_FILE" --set postgresql.enabled=false --set db.host=db.example.com
helm lint --strict "$CHART_DIR" -f "$VALUES_FILE" "${full_feature_args[@]}"

echo "==> Running helm template matrix checks"
render_and_validate install-bundled-db install bundled "" false
render_and_validate upgrade-bundled-db upgrade bundled "" false
render_and_validate install-external-db install external "" false --set postgresql.enabled=false --set db.host=db.example.com
render_and_validate upgrade-external-db upgrade external "" false --set postgresql.enabled=false --set db.host=db.example.com
render_and_validate install-full-features install external "${RELEASE_NAME}-" true "${full_feature_args[@]}"
render_and_validate upgrade-full-features upgrade external "${RELEASE_NAME}-" true "${full_feature_args[@]}"

echo "==> Running helm template negative validation checks"
assert_template_fails missing-signing-key "server.badges.signingKey is required"
assert_template_fails invalid-db-tls-ssl-mode "db.sslMode must be require" \
  -f "$VALUES_FILE" \
  --set db.tls.mode=verify-full \
  --set db.tls.caCert=dummy-ca

echo "All Helm chart checks passed."
