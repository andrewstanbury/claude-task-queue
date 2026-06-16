# Project tasks. `make test` runs the full gate — the same ./check.sh CI runs.
.PHONY: test check lint flow

test:
	./check.sh

check: test
lint: test

# Render the workflow diagram (the one sanctioned human-facing artifact, see flow.sh).
flow:
	@./flow.sh
