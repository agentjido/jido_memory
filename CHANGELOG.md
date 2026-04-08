# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

## [Unreleased]

### Added

- Provider-first runtime dispatch through `Jido.Memory.Provider`
- Built-in `Jido.Memory.Provider.Basic`
- Provider alias resolution through `Jido.Memory.ProviderRegistry`
- Provider bootstrap helper via `Jido.Memory.ProviderBootstrap`
- Canonical provider-facing structs:
  - `Scope`
  - `Hit`
  - `RetrieveResult`
  - `Explanation`
  - `CapabilitySet`
  - `ProviderInfo`
  - `IngestRequest`
  - `IngestResult`
  - `ConsolidationResult`
- Canonical runtime operations:
  - `retrieve/3`
  - `capabilities/2`
  - `info/2`
  - `ingest/3`
  - `explain_retrieval/3`
  - `consolidate/2`
- Compatibility alias `resolve_runtime/3`
- Canonical retrieval action `Jido.Memory.Actions.Retrieve`
- Shared provider contract test helper in `Jido.Memory.Testing.ProviderContractCase`
- External adapter package scaffolds:
  - `jido_memory_mempalace`
  - `jido_memory_mem0`

### Changed

- `retrieve/3` is now the canonical read path and returns `RetrieveResult`
- `recall/2` and `recall/3` now unwrap `RetrieveResult` hits into bare records
- `Jido.Memory.ETSPlugin` exposes both `memory.retrieve` and `memory.recall`
- `Jido.Memory.Query` now carries provider-specific `extensions`
