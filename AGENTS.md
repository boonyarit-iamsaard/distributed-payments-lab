# Agent guidance

`AGENTS.md` is the source for repository instructions. `CLAUDE.md` is a relative symlink to `AGENTS.md`; edit `AGENTS.md` directly.
`CONTEXT.md` contains the domain glossary. The project roadmap lives in `docs/roadmap.md`.

## Project roadmap

Before planning a lesson, implementing a lab exercise, or proposing architecture changes, read [the Distributed Payments Weekend Lab roadmap](docs/roadmap.md). Treat the roadmap as planned work, not evidence of completed implementation or learning.

## Markdown maintenance

- Run `make help` to see the maintenance commands.
- Run `make format` to format Markdown and apply lint fixes. Run `make check` before handoff to verify formatting and lint rules without changing files.
- Use `pnpm dlx` for Prettier and markdownlint-cli2. Keep their dependencies in pnpm's external cache; do not add local `node_modules` or install these tools globally.
- If a command fails because of sandbox or network restrictions, request elevated sandbox access and rerun the underlying `pnpm dlx` command. Delegation is permitted, but it does not bypass sandbox permissions.
- Format and lint `AGENTS.md` with the other Markdown files. `CLAUDE.md` shares the same content through its symlink.

## Agent skills

### Issue tracker

Track issues and specs as local markdown under `.scratch/<feature>/`. Before creating, fetching, or updating tickets, read `docs/agents/issue-tracker.md`.

### Triage labels

Use the five default triage labels. Before triaging issues or changing their triage status, read `docs/agents/triage-labels.md`.

### Domain docs

Use a single-context layout: root `CONTEXT.md` and `docs/adr/`. Before exploring the codebase or proposing domain changes, read `docs/agents/domain.md`.
