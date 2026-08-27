#!/usr/bin/env bash
# Run the performance suite on its own.
#
# It is excluded from the normal test run on purpose. The other suites drive
# Core ML concurrently, which saturates the Neural Engine queue and makes the
# numbers meaningless: a 31 ms embedding was measured at 494 ms under load,
# inverting the ANE-versus-CPU comparison entirely.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "Running benchmarks alone. Close anything else using the Neural Engine."
PFAMIE_BENCH=1 swift test -c release --package-path PfamIEKit --filter Performance 2>&1 \
    | grep -E "protein model|centroid search|Field Guide|SRC \(|✔|✘|Test run"
