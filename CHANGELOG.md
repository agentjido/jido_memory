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
