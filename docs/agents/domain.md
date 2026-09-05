# Domain Docs

This repo uses a single-context layout, with `CONTEXT.md` at the repo root and architecture decision records in `docs/adr/`.

## Before exploring, read these

- Read root `CONTEXT.md` for domain context and resolved terminology. Repository instructions live in `AGENTS.md`.
- Read ADRs in `docs/adr/` that touch the area you are about to work in.

If domain documentation or the ADR directory is absent, proceed silently. The `/domain-modeling` skill creates domain material lazily when terms or decisions are resolved.

## File structure

- `CONTEXT.md`: separate domain context document.
- `AGENTS.md`: repository instructions and engineering skill configuration.
- `CLAUDE.md`: relative symlink to `AGENTS.md`.
- `docs/adr/`: architecture decision records, created as decisions are recorded.

## Use the glossary's vocabulary

When naming a domain concept in an issue, proposal, hypothesis, or test, use the term defined in `CONTEXT.md`.

If a needed concept is absent, reconsider whether it belongs in the domain or note the gap for `/domain-modeling`.

## Flag ADR conflicts

If a proposal contradicts an existing ADR, identify the ADR and explain why the decision merits reopening.
