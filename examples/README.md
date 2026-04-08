# Examples

This folder holds runnable example scripts for `jido_memory`.

The example modules live under [`examples/support/memory_agent_examples.exs`](/Users/mhostetler/Source/OrigJido/proj_jido_memory/jido_memory/examples/support/memory_agent_examples.exs) and are loaded explicitly by scripts and tests. They are not part of the production compile path.

## Run The Demo

From the `jido_memory` repo root:

```bash
mix run examples/memory_agent_demo.exs
```

or:

```bash
mix example.memory
```

The demo proves two integration paths:

- A plain `Jido.Agent` with `Jido.Memory.BasicPlugin` can remember and retrieve notes.
- An AI-enabled Jido agent can expose memory retrieval as a tool through `jido_ai`.

The AI example is intentionally deterministic. It uses `Jido.AI.Actions.ToolCalling.ExecuteTool` to exercise the memory tool path without requiring live LLM credentials.

## Test Coverage

Focused example smoke coverage lives in [`test/examples/memory_agent_example_test.exs`](/Users/mhostetler/Source/OrigJido/proj_jido_memory/jido_memory/test/examples/memory_agent_example_test.exs).

Example tests are tagged `:examples` and excluded from the default `mix test` run. Execute them explicitly with:

```bash
mix test --only examples
```
