# Review-only Bash launcher. Default is dry-run; live execution requires separate approval.
quality_once() {
  local quality_rc
  if (
    set -o pipefail
    export LC_ALL=C
    case "${1:---dry-run}" in
      --dry-run) quality_args=(--dry-run) ;;
      --execute) quality_args=(--execute --standard-pricing-reviewed-2026-10-15 --prior-charge-and-overall-budget-reviewed) ;;
      *) exit 2 ;;
    esac
    command -v curl >/dev/null && command -v sha256sum >/dev/null && command -v timeout >/dev/null || exit 2
    quality_curl_version=$(curl --disable --version) || exit 2
    [[ "$quality_curl_version" =~ ^curl\ ([0-9]+)\.([0-9]+)\.([0-9]+)\  ]] || exit 2
    (( 10#${BASH_REMATCH[1]} > 8 || (10#${BASH_REMATCH[1]} == 8 && 10#${BASH_REMATCH[2]} >= 4) )) || exit 2
    ulimit -c 0 || exit 2
    ulimit -t 10 || exit 2
    quality_source=$(curl --disable --fail --silent --show-error --proto '=https' --tlsv1.2 --max-redirs 0 --connect-timeout 5 --max-time 10 --max-filesize 131072 'https://raw.githubusercontent.com/Ou931023/pet_companion_app/d7c7dd3c1fedb7a7575c9e13502549ba8d30770d/scripts/companion_quality.cjs' && printf '\001') || exit 2
    quality_source=${quality_source%$'\001'}
    test "${#quality_source}" -le 131072 || exit 2
    quality_sha=$(printf '%s' "$quality_source" | sha256sum) || exit 2
    test "${quality_sha%% *}" = '93c8043578a56d51a13e23f916797c20a013ba68efd675db69ad0106ac452230' || exit 2
    printf '%s' "$quality_source" | timeout --signal=TERM --kill-after=2s 95s \
      env -u NODE_OPTIONS -u NODE_PATH -u DEBUG -u NODE_USE_ENV_PROXY -u NODE_DEBUG -u NODE_DEBUG_NATIVE -u NODE_V8_COVERAGE -u NODE_REDIRECT_WARNINGS -u NODE_TLS_REJECT_UNAUTHORIZED \
      node --max-old-space-size=64 --max-http-header-size=8192 - "${quality_args[@]}"
  ); then
    quality_rc=0
  else
    quality_rc=$?
  fi
  # Source and hash variables existed only in the ended subshell; cleanup cannot erase status.
  printf '{"launcherExitCode":%s}\n' "$quality_rc"
  return "$quality_rc"
}
quality_once --dry-run
