# LLM Usage Rules for Jido Memory

This document provides rules for LLM-based tools (Cursor, Claude, ChatGPT, etc.) when working with this codebase.

## Core Principles

1. **Schema-First Validation**: All data validation must use Zoi schemas, never ad-hoc guards or manual pattern matching
2. **Type Correctness**: Use @spec for all public functions; lean on Dialyzer
3. **Explicit Contracts**: Store behaviors are explicit @behaviour modules with documented callbacks
4. **Document Everything**: Public APIs must have @moduledoc and @doc with examples
5. **Conventional Commits**: Always use conventional commit format; no exceptions

## DO

✓ Use Zoi schemas for validation  
✓ Write @spec for all public functions  
✓ Add @doc with examples to all public functions  
✓ Create tests before implementing features  
✓ Use pattern matching with @behaviour callbacks  
✓ Pipe operators for function chaining  
✓ Use {:ok, value} | {:error, reason} tuples  
✓ Document side effects explicitly  
✓ Run `mix quality` before any commit  
✓ Use conventional commit format  

## DON'T

✗ Create ad-hoc validation functions (use Zoi)  
✗ Use String.to_atom/1 with untrusted input  
✗ Leave functions without @doc  
✗ Create new error types without centralizing in Error module  
✗ Use `override: true` in mix.exs dependencies  
✗ Add heavy external dependencies  
✗ Commit without passing tests  
✗ Use abbreviated variable names (except i, j, k in loops)  
✗ Leave TODO comments without issues  
✗ Ignore Dialyzer warnings  

## Zoi Schema Pattern

**Always** use this pattern for structs:

```elixir
defmodule Jido.Memory.MyModel do
  @schema Zoi.struct(
    __MODULE__,
    %{
      id: Zoi.string(),
      name: Zoi.string() |> Zoi.nullish(),
      count: Zoi.integer() |> Zoi.default(0)
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))
  
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
  
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs), do: Zoi.parse(@schema, attrs)
end
```

## Store Behavior Pattern

When implementing a new store:

```elixir
defmodule Jido.Memory.Store.NewAdapter do
  @behaviour Jido.Memory.Store
  
  @impl true
  def remember(_state, record) do
    # Implementation
    {:ok, record}
  end
  
  @impl true
  def recall(_state, query) do
    # Implementation
    {:ok, []}
  end
  
  @impl true
  def forget(_state, id) do
    # Implementation
    {:ok, true}
  end
end
```

## Query Building Pattern

Queries should be built with clear, chainable interfaces:

```elixir
query = Query.new()
  |> Query.with_classes([:semantic, :episodic])
  |> Query.with_tags_any(["market"])
  |> Query.limit(10)
  |> Query.order_by(:desc)
```

## Error Handling Pattern

Create domain-specific errors in a centralized Error module:

```elixir
defmodule Jido.Memory.Error do
  defmodule StoreError do
    defexception [:message, :details]
  end
end

# Usage
raise Jido.Memory.Error.StoreError, message: "Failed to connect", details: %{reason: :timeout}
```

## Testing Pattern

```elixir
defmodule Jido.Memory.MyModuleTest do
  use ExUnit.Case
  
  describe "function_name/1" do
    test "returns ok tuple on success" do
      {:ok, result} = MyModule.function_name(%{valid: :input})
      assert result.field == "expected"
    end
    
    test "returns error tuple on invalid input" do
      {:error, reason} = MyModule.function_name(%{invalid: :data})
      assert reason =~ "validation"
    end
  end
end
```

## Code Style Standards

- **Line Length**: Maximum 120 characters
- **Indentation**: 2 spaces
- **Function Signatures**: Multi-line if >80 characters
- **Documentation**: Explicit, with examples
- **Comments**: Rare; code should be self-documenting

```elixir
# Good
def long_function_name(param1, param2, param3, param4, param5) do
  # Implementation
end

# Also good (multi-line signature)
def long_function_name(
  param1,
  param2,
  param3,
  param4,
  param5,
  opts \\ []
) do
  # Implementation
end
```

## Commit Message Examples

```bash
git commit -m "feat(store): add postgres adapter with connection pooling"
git commit -m "fix(query): resolve edge case with null class filters"
git commit -m "docs(readme): clarify auto-capture signal patterns"
git commit -m "test(plugin): add coverage for concurrent memory access"
git commit -m "refactor(record): simplify validation logic"
git commit -m "perf(ets): optimize query filtering"
git commit -m "chore(deps): update jido to 2.0.0-rc.5"
```

## Pre-Commit Checklist

Before committing, verify:

```bash
mix format           # Code formatting
mix credo            # Linting
mix dialyzer         # Type checking
mix test             # Tests pass
mix coveralls.html   # Coverage >90%
mix doctor --raise   # All public APIs documented
mix quality          # Full quality suite
```

## Documentation Checklist

For any public module or function:

- [ ] Has `@moduledoc` (if module is public)
- [ ] Has `@doc` (if function is public)
- [ ] Has `@spec` with correct return types
- [ ] Includes usage example in @doc
- [ ] Documents parameters clearly
- [ ] Documents return values
- [ ] Documents possible errors
- [ ] Passes `mix doctor`

## Type Specification Examples

```elixir
# Simple function
@spec validate(map()) :: {:ok, term()} | {:error, term()}

# With options
@spec process(input, keyword()) :: {:ok, result} | {:error, reason}
  when input: any(), result: any(), reason: any()

# Union types
@spec normalize(term()) :: atom() | String.t()

# Callbacks
@callback store(state :: any(), record :: Record.t()) :: {:ok, Record.t()} | {:error, term()}
```

## Dialyzer Compliance

- No warnings allowed in CI
- Use `@type` for internal types
- Use `@spec` for all public functions
- Avoid `any()` except where truly necessary
- Document type contracts in @doc

## Performance Guidelines

- ETS queries are O(n) scans unless indexed
- Filter early to reduce result sets
- Document time complexity in @doc
- Consider memory implications of large result sets
- Profile with `:fprof` or similar before optimizing

## Dependency Guidelines

- Minimal, focused libraries only
- No "kitchen sink" dependencies
- Prefer stdlib when possible
- Lock versions in mix.lock
- Document why each dependency exists
- Keep dev/test dependencies separate

## Breaking Changes

Mark breaking changes in commits:

```bash
git commit -m "feat!: remove deprecated query_all/0 function"
git commit -m "refactor!: change Record.new/1 return type"
```

Breaking changes must:
- Be documented in CHANGELOG.md
- Bump MAJOR version in mix.exs
- Include migration guide in docs
