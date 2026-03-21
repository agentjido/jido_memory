# `.spec/decisions`

Use this folder for durable cross-cutting decisions that should stay aligned over time.

<!-- covers: spec.workspace.decisions_readme_present -->

## What Belongs Here

- ADRs that affect multiple authored subjects
- package-wide policy that should remain stable across changes
- durable decisions about verification or specification boundaries

## What Does Not Belong Here

- implementation plans for one branch
- temporary rollout notes
- roadmap, phase, or backlog material

## Workflow

1. Update `.spec/specs/` first.
2. Add or revise an ADR here only when the change is cross-cutting and durable.
3. Keep Git history and pull requests as the time dimension for how the decision evolved.
