#!/usr/bin/env bash
set -euo pipefail

# Sigil binary resolution
if [ -z "${SIGIL:-}" ]; then
  if command -v sigil >/dev/null 2>&1; then
    SIGIL="sigil"
  elif [ -x "/home/hatch/workspace/sigil/target/release/sigil" ]; then
    SIGIL="/home/hatch/workspace/sigil/target/release/sigil"
  else
    echo "Error: sigil binary not found on PATH or at /home/hatch/workspace/sigil/target/release/sigil. Set SIGIL=/path/to/sigil." >&2
    exit 1
  fi
fi

echo "Using Sigil compiler: $SIGIL"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== 1. Checking format (sigil fmt --check) ==="
$SIGIL fmt --check container/*.sigil tests/*.sigil test_runner.sigil db/*.sigil

echo "=== 2. Type checking (sigil check) ==="
$SIGIL check --root . test_runner.sigil

echo "=== 3. Running tests via SIR evaluator (sigil run) ==="
RUN_OUTPUT="$($SIGIL run --root . test_runner.sigil main)"
if [ "$RUN_OUTPUT" != "0" ]; then
  echo "Test failure in SIR evaluator: expected 0, got $RUN_OUTPUT" >&2
  exit 1
fi
echo "SIR evaluator tests passed (result = 0)"

echo "=== 4. Building and running native binary (sigil build) ==="
TMP_BIN="$(mktemp -t sigil_container_test_XXXXXX)"
$SIGIL build --root . test_runner.sigil main -o "$TMP_BIN"
NATIVE_STATUS=0
NATIVE_OUTPUT="$("$TMP_BIN")" || NATIVE_STATUS=$?
rm -f "$TMP_BIN"
if [ "$NATIVE_STATUS" -ne 0 ]; then
  echo "Native binary exited with status $NATIVE_STATUS" >&2
  exit "$NATIVE_STATUS"
fi
if [ "$NATIVE_OUTPUT" != "0" ]; then
  echo "Test failure in native binary: expected 0, got $NATIVE_OUTPUT" >&2
  exit 1
fi
echo "Native binary tests passed (result = 0)"

if [ -x "./tests/test_runtime_e2e.sh" ] && (command -v crun >/dev/null 2>&1 || command -v runc >/dev/null 2>&1); then
  echo "=== 5. Running real OCI runtime integration and negative tests ==="
  ./tests/test_runtime_e2e.sh
else
  echo "=== 5. Skipping real OCI runtime integration (neither runc nor crun found on PATH) ==="
fi

echo "=== All tests passed successfully! Evaluator and native match verified. ==="
