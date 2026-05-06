.PHONY: help lint shellcheck shfmt unit-tests integration-tests test setup-dokku act act-lint act-tests

help:
	@echo "Targets:"
	@echo "  lint               - shellcheck + shfmt"
	@echo "  shellcheck         - run shellcheck on all bash scripts"
	@echo "  shfmt              - run shfmt -d to check formatting"
	@echo "  unit-tests         - run bats tests/unit_*.bats"
	@echo "  integration-tests  - bring up Dokku in Docker, run bats tests"
	@echo "  test               - lint + unit-tests + integration-tests"
	@echo "  act-lint           - run lint job through act"
	@echo "  act-tests          - run tests job through act"
	@echo "  act                - run all act jobs"

SCRIPTS := commands install update config $(wildcard subcommands/*) common-functions functions help-functions service-list pre-start pre-delete post-app-clone-setup post-app-rename-setup
EXISTING_SCRIPTS := $(wildcard $(SCRIPTS))

shellcheck:
	@for f in $(EXISTING_SCRIPTS); do shellcheck -x "$$f"; done

shfmt:
	@if [ -n "$(EXISTING_SCRIPTS)" ]; then shfmt -d -i 2 -ci $(EXISTING_SCRIPTS); fi

lint: shellcheck shfmt

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
