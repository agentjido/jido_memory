# jido_memory Package

This subject captures the current package-level behavior that `jido_memory` ships today.

## Intent

Describe the stable, implemented behavior of the package before any future provider architecture work lands.

```spec-meta
id: jido_memory.package
kind: package
status: active
summary: jido_memory provides a structured record model, query model, store abstraction, ETS-backed runtime, and plugin/actions integration for Jido agents.
surface:
  - README.md
  - mix.exs
  - lib/jido_memory.ex
  - lib/jido_memory/record.ex
  - lib/jido_memory/query.ex
  - lib/jido_memory/store.ex
  - lib/jido_memory/store/ets.ex
  - lib/jido_memory/plugin.ex
  - lib/jido_memory/actions/*.ex
  - test/jido_memory_test.exs
  - test/jido_memory/plugin_test.exs
  - test/jido_memory/actions_test.exs
```

## Requirements

```spec-requirements
- id: jido_memory.package.structured_memory_contract
  statement: The package shall provide structured record and query contracts plus a runtime facade and store behavior for writing, retrieving, and deleting memory records.
  priority: must
  stability: stable
- id: jido_memory.package.default_ets_path
  statement: The default shipped memory path shall be ETS-backed and use ETS as the authoritative store unless the caller supplies another store implementation.
  priority: must
  stability: stable
- id: jido_memory.package.plugin_and_actions
  statement: The package shall provide a Jido plugin and explicit actions for remember, recall, and forget flows.
  priority: must
  stability: stable
- id: jido_memory.package.auto_capture
  statement: The plugin shall support auto-capture of configured signal patterns into structured memory records.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: jido_memory.package.agent_isolation
  given:
    - two agents write memory without overriding namespace
  when:
    - each agent recalls its own memories
  then:
    - each agent sees only its own namespace-scoped records
  covers:
    - jido_memory.package.structured_memory_contract
- id: jido_memory.package.auto_capture_flow
  given:
    - a mounted plugin with matching capture patterns
  when:
    - the agent receives a matching signal
  then:
    - the signal is persisted as a structured memory record
  covers:
    - jido_memory.package.auto_capture
    - jido_memory.package.plugin_and_actions
```

## Verification

```spec-verification
- kind: source_file
  target: README.md
  covers:
    - jido_memory.package.structured_memory_contract
    - jido_memory.package.default_ets_path
    - jido_memory.package.plugin_and_actions
    - jido_memory.package.auto_capture
- kind: command
  target: mix test test/jido_memory_test.exs
  execute: true
  covers:
    - jido_memory.package.structured_memory_contract
    - jido_memory.package.default_ets_path
    - jido_memory.package.agent_isolation
- kind: command
  target: mix test test/jido_memory/plugin_test.exs test/jido_memory/actions_test.exs
  execute: true
  covers:
    - jido_memory.package.plugin_and_actions
    - jido_memory.package.auto_capture
    - jido_memory.package.auto_capture_flow
```
