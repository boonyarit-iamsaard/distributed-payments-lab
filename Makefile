PNPM := pnpm dlx

.DEFAULT_GOAL := help

.PHONY: help format format-md lint lint-md check

help: ## Show maintenance commands
	@awk 'BEGIN {FS = ":.*?## "} /^[a-z-]+:.*?## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

format: format-md ## Format Markdown and apply lint fixes

format-md: ## Format Markdown and apply lint fixes
	$(PNPM) prettier --write "**/*.md"
	$(PNPM) markdownlint-cli2 --fix "**/*.md" "!node_modules/**" "!target/**" "!.agents/**" "!.codex/**"

lint: lint-md ## Check Markdown without changing files

lint-md: ## Check Markdown formatting and lint rules
	$(PNPM) prettier --check "**/*.md"
	$(PNPM) markdownlint-cli2 "**/*.md" "!node_modules/**" "!target/**" "!.agents/**" "!.codex/**"

check: lint ## Run all maintenance checks without changing files
