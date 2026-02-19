# Contributing to Jido Memory

Thank you for your interest in contributing to Jido Memory!

## Getting Started

1. **Fork and Clone**
   ```bash
   git clone https://github.com/agentjido/jido_memory.git
   cd jido_memory
   ```

2. **Set Up Development Environment**
   ```bash
   mix setup
   ```

3. **Run Tests**
   ```bash
   mix test
   ```

4. **Check Code Quality**
   ```bash
   mix quality
   ```

## Development Workflow

### Making Changes

1. Create a feature branch from `main`
   ```bash
   git checkout -b feat/your-feature-name
   ```

2. Make your changes and write tests
   - All public APIs must have documentation
   - Tests should achieve >90% coverage
   - Run `mix quality` to check formatting, linting, and documentation

3. Commit with conventional commits (see below)
   ```bash
   git commit -m "feat(module): description of change"
   ```

4. Push and create a pull request
   ```bash
   git push origin feat/your-feature-name
   ```

### Conventional Commits

This project follows [Conventional Commits](https://www.conventionalcommits.org/).

**Format:**
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation changes
- `style` - Formatting, no code change
- `refactor` - Code change, no fix or feature
- `perf` - Performance improvement
- `test` - Adding/fixing tests
- `chore` - Maintenance, deps, tooling
- `ci` - CI/CD changes

**Examples:**
```bash
git commit -m "feat(store): add postgres adapter"
git commit -m "fix(query): resolve filter with null tags"
git commit -m "docs(readme): clarify namespace modes"
git commit -m "feat!: breaking change to Record schema"
```

### Code Quality Standards

- **Formatting**: Run `mix format` (enforced in CI)
- **Linting**: Run `mix credo` 
- **Type checking**: Run `mix dialyzer`
- **Documentation**: Run `mix doctor --raise` (all public APIs must be documented)
- **Tests**: Aim for >90% coverage with `mix coveralls.html`

## Testing

```bash
# Run all tests
mix test

# Run with coverage
mix coveralls.html

# Run a specific test file
mix test test/jido_memory_test.exs

# Run a specific test
mix test test/jido_memory_test.exs:12
```

## Documentation

All public modules and functions must have documentation.

```elixir
defmodule MyModule do
  @moduledoc """
  Brief description of this module.
  
  ## Overview
  
  Longer description explaining what this module does.
  
  ## Examples
  
      iex> MyModule.do_thing(:input)
      {:ok, :result}
  """
  
  @doc """
  Does a specific thing.
  
  ## Parameters
  
    * `input` - Description of input
    * `opts` - Keyword list of options
      * `:timeout` - Timeout in milliseconds (default: 5000)
  
  ## Returns
  
    * `{:ok, result}` - On success
    * `{:error, reason}` - On failure
  """
  @spec do_thing(term(), keyword()) :: {:ok, term()} | {:error, term()}
  def do_thing(input, opts \\ []) do
    # Implementation
  end
end
```

Generate docs locally:
```bash
mix docs
open doc/index.html
```

## Pull Request Process

1. Ensure all tests pass: `mix test`
2. Ensure code quality passes: `mix quality`
3. Update documentation if needed
4. Provide a clear description of changes
5. Reference any related issues
6. Squash commits before merging if requested

## Questions or Issues?

- Open an issue on GitHub for bugs or feature requests
- Join discussions in the Jido community channels

Thank you for contributing!
