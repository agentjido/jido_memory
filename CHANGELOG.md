# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Canonical provider contract via `Jido.Memory.Provider`
- Built-in `Jido.Memory.Provider.Basic` and `Jido.Memory.Provider.Tiered`
- `Jido.Memory.LongTermStore` and default ETS-backed long-term backend
- Built-in `Jido.Memory.LongTermStore.Postgres` as the first supported durable long-term backend
- Provider-aware runtime helpers including `retrieve/3`, `capabilities/2`, `info/3`, and `consolidate/2`
- Common `Jido.Memory.Plugin` plus canonical `memory.retrieve` action
- External-provider interop helpers and bootstrap ownership guidance
- Tiered retrieval explainability and provider-direct lifecycle inspection
- Release-gated follow-on acceptance matrix and durable-storage operations guides

### Changed

- `jido_memory` is now documented as the unified Jido memory package with built-in provider choices
- `recall/2`, `Jido.Memory.ETSPlugin`, and tuple-style runtime results remain supported for compatibility
- `jido_memory_os` is documented as a standalone advanced library rather than a release-critical built-in provider path

### Known Limits

- Tiered explainability remains intentionally bounded and does not replace journaling or replay
- The built-in Postgres backend currently uses namespace-scoped fetches with overlapping query filtering in Elixir
- Redis and other durable backends remain follow-on work rather than first-party release paths
- `mix quality` and `mix test.acceptance` gate only the supported release matrix, not every possible third-party provider combination

## [0.1.0] - 2025-02-19

### Added

- Initial release of Jido Memory
- ETS-backed in-memory store for agent memory records
- Structured `Jido.Memory.Record` model with support for episodic, semantic, procedural, and working memory
- `Jido.Memory.Query` for flexible memory filtering and retrieval
- `Jido.Memory.ETSPlugin` for integration with Jido agents
- Memory actions: `remember`, `recall`, `forget`
- Auto-capture hooks for AI and non-LLM signal flows
- Per-agent and shared namespace modes
- RAG-ready schema with embedding field support
