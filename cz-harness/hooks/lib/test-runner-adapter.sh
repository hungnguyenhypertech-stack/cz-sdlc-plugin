#!/usr/bin/env bash
# Pluggable test-runner adapter. Reference implementation: pytest (decision recorded
# 2026-07-27, plan §14.1). Other runners (vitest/jest, JUnit/Maven, go test) plug in
# by implementing the same two functions and swapping CZ_TEST_RUNNER.
set -euo pipefail

CZ_TEST_RUNNER="${CZ_TEST_RUNNER:-pytest}"

# cz_run_tests <test-path-or-node-id...> -> exit 0 on ALL PASS, non-zero otherwise.
# Writes raw runner output to stdout; caller redirects to the red/green log file.
cz_run_tests() {
  case "$CZ_TEST_RUNNER" in
    pytest)
      # -q quiet, --tb=short keeps evidence logs readable by non-coder PMs via /cz:explain
      pytest -q --tb=short "$@"
      ;;
    vitest)
      npx vitest run "$@"
      ;;
    jest)
      npx jest "$@"
      ;;
    go)
      go test "$@"
      ;;
    *)
      echo "[cz-harness] unknown CZ_TEST_RUNNER: $CZ_TEST_RUNNER" >&2
      exit 2
      ;;
  esac
}

# cz_tests_all_failed <log-file> -> exit 0 if the run recorded at least one failure
# and zero errors that would make the "fail" meaningless (e.g. collection errors
# masquerading as test failures). Reference pytest implementation.
cz_tests_all_failed() {
  local log="$1"
  case "$CZ_TEST_RUNNER" in
    pytest)
      grep -qE '^[0-9]+ failed' "$log" && ! grep -qE 'ERROR' "$log"
      ;;
    vitest|jest)
      grep -qiE 'fail(ed)?' "$log"
      ;;
    go)
      grep -qE '^--- FAIL' "$log"
      ;;
    *)
      return 1
      ;;
  esac
}

# cz_tests_all_passed <log-file>
cz_tests_all_passed() {
  local log="$1"
  case "$CZ_TEST_RUNNER" in
    pytest)
      grep -qE '^[0-9]+ passed' "$log" && ! grep -qE '(failed|error)' "$log"
      ;;
    vitest|jest)
      ! grep -qiE 'fail(ed)?' "$log" && grep -qiE 'pass(ed)?' "$log"
      ;;
    go)
      grep -qE '^ok' "$log"
      ;;
    *)
      return 1
      ;;
  esac
}
