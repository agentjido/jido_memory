# AI Agent Instructions for Jido Memory

This document provides guidance for AI agents (Cursor, Claude, etc.) working on the Jido Memory codebase.

## Project Overview

**Jido Memory** is a data-driven, ETS-backed memory system for Jido agents. It provides structured storage, retrieval, and auto-capture of agent interactions across episodic, semantic, procedural, and working memory classes.

### Core Concepts

- **Record**: The fundamental unit of memory (Jido.Memory.Record)
- **Store**: Pluggable storage backend (currently ETS)
- **Query**: Flexible filtering and retrieval interface
- **Plugin**: Integration point with Jido agents
- **Auto-capture**: Signal-driven memory recording

## Development Quick Start

```bash
# Setup
mix setup

# Development loop
mix format
mix credo
mix test
mix doctor --raise

# Full quality check
mix quality
```

## File Structure

- `lib/jido_memory.ex` - Main module and entry points
- `lib/jido_memory/record.ex` - Record schema and validation
- `lib/jido_memory/query.ex` - Query builder and filtering
- `lib/jido_memory/store.ex` - Store behavior and contracts
- `lib/jido_memory/store/ets.ex` - ETS implementation
- `lib/jido_memory/plugin.ex` - Jido plugin implementation
- `lib/jido_memory/actions/` - Signal-driven action modules
- `lib/jido_memory/runtime.ex` - Runtime API

## Key Design Patterns

### 1. Record Validation with Zoi

Records use Zoi schemas for validation:

```elixir
defmodule Jido.Memory.Record do
  @schema Zoi.struct(__MODULE__, %{
    id: Zoi.string(),
    namespace: Zoi.string() |> Zoi.nullish(),
    class: Zoi.atom() |> Zoi.one_of([:episodic, :semantic, :procedural, :working]),
    # ... more fields
  })
  
  @type t :: unquote(Zoi.type_spec(@schema))
  
  def schema, do: @schema
  def new(attrs), do: Zoi.parse(@schema, attrs)
end
```

### 2. Store Adapter Pattern

Stores implement the `Jido.Memory.Store` behavior:

```elixir
defmodule Jido.Memory.Store.ETS do
  @behaviour Jido.Memory.Store
  
  @impl true
  def remember(_state, _record), do: ...
  
  @impl true
  def recall(_state, _query), do: ...
end
```

To add a new store (Postgres, SQLite, etc.):
1. Create `lib/jido_memory/store/adapter_name.ex`
2. Implement `Jido.Memory.Store` callbacks
3. Update documentation

### 3. Action Modules

Actions are driven by signal routes. Follow the pattern:

```elixir
defmodule Jido.Memory.Actions.Remember do
  @behaviour Jido.Action
  
  @impl true
  def run(context, input, _opts) do
    # Transform input to record
    # Call store.remember()
    # Return {:ok, %{last_memory_id: ...}}
  end
end
```

## Testing Guidelines

- Test files mirror lib structure: `test/jido_memory/module_test.exs`
- Use ExUnit with property-based testing via StreamData where appropriate
- Aim for >90% coverage
- Mock external dependencies with Mimic

```bash
mix test                # Run all tests
mix coveralls.html      # Coverage report
mix test --watch        # Watch mode (requires mix-watch)
```

## Documentation Requirements

- All public modules must have `@moduledoc`
- All public functions must have `@doc` and `@spec`
- Examples should be runnable as doctests
- Use `@moduledoc false` for internal modules

Check coverage:
```bash
mix doctor --raise
```

## Common Tasks

### Adding a New Memory Class

1. Update `Record` schema to validate new class
2. Update CHANGELOG.md
3. Add tests in `test/jido_memory/record_test.exs`
4. Update README.md with example

### Adding a New Store Adapter

1. Create `lib/jido_memory/store/new_adapter.ex`
2. Implement all `Jido.Memory.Store` callbacks
3. Add tests in `test/jido_memory/store_new_adapter_test.exs`
4. Document usage in README.md

### Adding a New Auto-Capture Signal Pattern

1. Update `lib/jido_memory/plugin.ex` capture logic
2. Add corresponding action in `lib/jido_memory/actions/`
3. Update capture_signal_patterns documentation
4. Add tests in `test/jido_memory/plugin_test.exs`

## Code Style

- Line length: 120 characters
- Use meaningful variable names
- Prefer pipe operators for chaining
- Document side effects explicitly
- Use `:ok` / `:error` tuples consistently

## Error Handling

Create a `Jido.Memory.Error` module for consistent error handling:

```elixir
defmodule Jido.Memory.Error do
  defmodule InvalidRecordError do
    defexception [:message]
  end
  
  defmodule StoreError do
    defexception [:message, :reason]
  end
end
```

## Dependencies

- `:jido` - Core Jido framework
- `:jido_action` - Action definitions
- `:jido_ai` - AI integration (if applicable)

Do NOT add heavy dependencies. Prefer minimal, focused libraries.

## Debugging

```bash
# Interactive shell with deps loaded
iex -S mix

# Run with verbose output
mix test --verbose

# Dialyzer (static type checking)
mix dialyzer
```

## Performance Considerations

- ETS is in-memory and fast but not persistent
- Filter early in Query to reduce result sets
- Consider indexing strategies for large memory stores
- Document time complexity of operations

## Release Process

```bash
# Check everything
mix quality
mix test

# Update CHANGELOG.md with release notes
# Commit: "chore(release): 0.2.0"
git tag v0.2.0
git push && git push --tags

# Publish to Hex
mix hex.publish
```

## Useful Resources

- [Jido Documentation](https://github.com/agentjido/jido)
- [Zoi Schema Library](https://github.com/agentjido/zoi)
- [Jido.Action](https://github.com/agentjido/jido_action)
- [Elixir Docs](https://elixir-lang.org/docs.html)

## Contact & Support

- Open issues on GitHub
- Discuss in Jido community channels
