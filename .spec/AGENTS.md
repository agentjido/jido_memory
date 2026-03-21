# `.spec` Agent Guide

Use this folder to maintain authored Spec Led Development subjects for `jido_memory`.

<!-- covers: spec.workspace.agents_present -->

## First Read

1. Read `.spec/README.md`.
2. Read `.spec/decisions/README.md` before adding any ADRs.
3. Read the existing subject specs in `.spec/specs/`.
4. Read supporting design docs in `docs/` when a subject depends on them.

## Working Rules

- Keep one subject per file.
- Put normative statements in `spec-requirements`.
- Add `spec-scenarios` only when `given` / `when` / `then` improves clarity.
- Keep proposals and roadmap material out of `.spec/specs/` unless the subject is explicitly marked draft and describes a real repository-level contract.
- Keep durable cross-cutting decisions in `.spec/decisions/`, not in branch-local notes.
- Prefer command verifications for behavior and source-file verifications for stable document boundaries.
- Keep verification targets repository-root-relative.
- Treat `.spec` as current truth for the repository, not as a changelog.

## Current Adoption Notes

- The workspace is bootstrapped and `.spec/state.json` has been generated.
- Local `mix spec.*` runs from `jido_memory` are available now that the published Hex dependency set resolves cleanly.
- Run `mix spec.verify --debug` and `mix spec.check` from `jido_memory` directly to keep the state fresh.
