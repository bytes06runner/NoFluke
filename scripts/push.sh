#!/usr/bin/env bash
# Scans for secrets, then pushes. GitHub has been rejecting some pushes with transient server errors, so this retries.
set -euo pipefail
gitleaks detect --no-banner --redact --source . >/dev/null 2>&1 || { echo "gitleaks found something: not pushing"; exit 1; }
for i in 1 2 3 4 5 6; do
  if git push -q origin main 2>/dev/null; then echo "pushed $(git rev-parse --short HEAD)"; exit 0; fi
  sleep $((i * 5))
done
echo "push failed after retries"; exit 1
