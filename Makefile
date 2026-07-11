# Project tasks. `make test` runs the full gate — the same ./check.sh CI runs.
.PHONY: test check lint

test:
	./check.sh

check: test
lint: test
