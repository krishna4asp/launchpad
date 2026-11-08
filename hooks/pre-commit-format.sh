#!/usr/bin/env bash
# Pre-commit hook: verify code formatting
# Runs dotnet format in verify mode — fails if any files need formatting.

set -euo pipefail

echo "Checking code formatting..."

if dotnet format --verify-no-changes --verbosity quiet 2>/dev/null; then
    echo "Format check passed."
else
    echo "Format check failed. Run 'dotnet format' to fix formatting issues."
    exit 1
fi
