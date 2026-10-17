#!/usr/bin/env bash
# Runs every milestone test headless and prints a one-line summary per suite.
# Usage: bash tools/run_tests.sh        (from the project folder)
cd "$(dirname "$0")/.." || exit 1
status=0
for test in tests/test_milestone_*.gd; do
	out=$(godot --headless --script "res://$test" 2>&1)
	code=$?
	summary=$(echo "$out" | grep "checks passed")
	echo "$(basename "$test" .gd): ${summary:-no summary} (exit $code)"
	echo "$out" | grep "^FAIL" | sed 's/^/    /'
	errors=$(echo "$out" | grep -E "SCRIPT ERROR|Parse Error|Compile Error" | grep -v "deliberately")
	if [ -n "$errors" ]; then
		echo "$errors" | sort | uniq -c | head -5 | sed 's/^/    /'
		code=1
	fi
	[ $code -ne 0 ] && status=1
done
exit $status
