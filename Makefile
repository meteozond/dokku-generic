.PHONY: help lint shellcheck shfmt bashate unit-tests integration-tests test setup-dokku act act-lint act-tests

help:
	@echo "Targets:"
	@echo "  lint               - shellcheck + shfmt + bashate"
	@echo "  shellcheck         - static analyzer for bash (semantic bugs)"
	@echo "  shfmt              - formatting check (2-space indent, ci)"
	@echo "  bashate            - style linter (line length, whitespace, keyword layout)"
	@echo "  unit-tests         - run bats tests/unit_*.bats"
	@echo "  integration-tests  - bring up Dokku in Docker, run bats tests"
	@echo "  test               - lint + unit-tests + integration-tests"
	@echo "  act-lint           - run lint job through act"
	@echo "  act-tests          - run tests job through act"
	@echo "  act                - run all act jobs"

SCRIPTS := commands install update config $(wildcard subcommands/*) common-functions functions help-functions service-list pre-start pre-delete post-app-clone-setup post-app-rename-setup
EXISTING_SCRIPTS := $(wildcard $(SCRIPTS))

# E003: indent (we use 2-space per shfmt, not bashate's default 4)
# E010, E011: false positives on `for X; do Y; done` and `if X; then Y; fi` one-liners
BASHATE_IGNORE := E003,E010,E011

shellcheck:
	@for f in $(EXISTING_SCRIPTS); do shellcheck -x "$$f"; done

shfmt:
	@if [ -n "$(EXISTING_SCRIPTS)" ]; then shfmt -d -i 2 -ci $(EXISTING_SCRIPTS); fi

bashate:
	@if [ -n "$(EXISTING_SCRIPTS)" ]; then bashate --ignore=$(BASHATE_IGNORE) --max-line-length=200 $(EXISTING_SCRIPTS); fi

lint: shellcheck shfmt bashate

unit-tests:
	bats tests/unit_*.bats

setup-dokku:
	./tests/setup-dokku.sh

integration-tests: setup-dokku
	bats tests/service_*.bats

test: lint unit-tests integration-tests

act-lint:
	act -j lint --privileged --bind

act-tests:
	act -j tests --privileged --bind

act: act-lint act-tests
