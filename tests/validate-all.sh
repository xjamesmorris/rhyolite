#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash "${ROOT}/tests/validate-harness-contract.sh"
bash "${ROOT}/tests/test-report-repair.sh"
bash "${ROOT}/tests/validate-plugin.sh"
