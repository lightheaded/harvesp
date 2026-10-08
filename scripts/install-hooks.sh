#!/usr/bin/env bash
# install-hooks.sh - turn on the HarvESP git hooks in this clone.
#
# It sets core.hooksPath to .githooks. The hooks in .githooks run the guard
# first. Then they run your global hooks, if you have them.
# It also makes the local denylist file inside .git, if it is missing.
set -euo pipefail

top=$(git rev-parse --show-toplevel)
cd "$top"

chmod +x .githooks/pre-commit .githooks/commit-msg .githooks/pre-push \
	.githooks/post-checkout .githooks/post-commit .githooks/post-merge \
	scripts/privacy-guard.sh
git config core.hooksPath .githooks

deny=$(git rev-parse --git-path info/privacy-denylist)
mkdir -p "$(dirname "$deny")"
if [ ! -e "$deny" ]; then
	cat >"$deny" <<'TXT'
# HarvESP local denylist. This file is inside .git. Git never commits it.
# Write one term on each line. The match ignores case and finds the term
# inside longer words. A line that starts with # is a comment.
# Add the private words that only you know: names of people and places,
# device names, network names and the names of your other projects.
TXT
	echo "Created $deny"
fi

echo "Hooks are on: core.hooksPath=.githooks"
echo "Add your private terms to: $deny"
