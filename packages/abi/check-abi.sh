#!/usr/bin/env bash
# Regenerates the ABIs and fails if the result differs from what git has
# (index, or HEAD for a clean index). Used by `npm run check-abi`,
# `make check-abi` and the pre-commit hook.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
GENERATED="packages/abi/src/generated.ts"

npm run --silent abi >/dev/null 2>&1 || {
    echo "check-abi: ABI generation failed (run 'npm run abi' to see the error)" >&2
    exit 1
}

if ! git ls-files --error-unmatch "$GENERATED" >/dev/null 2>&1; then
    echo "check-abi: $GENERATED is not tracked. Run: git add $GENERATED" >&2
    exit 1
fi

if ! git diff --quiet -- "$GENERATED"; then
    echo "check-abi: the contract ABIs changed and $GENERATED is not staged." >&2
    echo "           Review the diff, then: git add $GENERATED" >&2
    git --no-pager diff --stat -- "$GENERATED" >&2
    exit 1
fi

echo "check-abi: ABIs up to date"
