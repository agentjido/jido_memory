# Spec Workspace

This subject defines the local contract for how `jido_memory` uses `.spec/`.

## Intent

Keep the workspace small, current-truth oriented, and clearly separated from supporting design material.

```spec-meta
id: spec.system
kind: policy
status: active
summary: Local workspace contract for authored specs and supporting design boundaries in jido_memory.
surface:
  - .spec/README.md
  - .spec/AGENTS.md
  - .spec/decisions/README.md
  - .spec/specs/**/*.spec.md
  - docs/rfcs/*.md
```

## Requirements

```spec-requirements
- id: spec.workspace.readme_present
  statement: The repository shall include a .spec/README.md that explains the purpose, layout, and workflow for the local Spec Led workspace.
  priority: must
  stability: stable
- id: spec.workspace.agents_present
  statement: The repository shall include a .spec/AGENTS.md that gives local operating guidance for agents editing current-truth subjects.
  priority: must
  stability: stable
- id: spec.workspace.decisions_readme_present
  statement: The repository shall include a .spec/decisions/README.md that explains when durable ADRs belong in the workspace.
  priority: must
  stability: stable
- id: spec.workspace.current_truth_boundary
  statement: Current-truth subject specs shall live in .spec/specs/, while supporting RFCs and design notes shall stay outside that directory.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/README.md
  covers:
    - spec.workspace.readme_present
- kind: source_file
  target: .spec/AGENTS.md
  covers:
    - spec.workspace.agents_present
- kind: source_file
  target: .spec/decisions/README.md
  covers:
    - spec.workspace.decisions_readme_present
- kind: source_file
  target: docs/rfcs/0001-canonical-memory-provider-architecture.md
  covers:
    - spec.workspace.current_truth_boundary
```
