#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
qa_test_dir="$(mktemp -d)"
trap 'rm -rf "$qa_test_dir"' EXIT
swiftc -parse-as-library packages/rn-qa-overlay/ios/QaLinearClient.swift tests/linear/CoreChecks.swift -o "$qa_test_dir/linear-checks"
"$qa_test_dir/linear-checks"
