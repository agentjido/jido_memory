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

- A plain `Jido.Agent` with `Jido.Memory.ETSPlugin` can remember and recall notes.
- An AI-enabled Jido agent can expose memory recall as a tool through `jido_ai`.

The AI example is intentionally deterministic. It uses `Jido.AI.Actions.ToolCalling.ExecuteTool` to exercise the memory tool path without requiring live LLM credentials.

## Test Coverage

Focused integration coverage for the example lives in [`test/jido_memory/examples_integration_test.exs`](/Users/mhostetler/Source/OrigJido/proj_jido_memory/jido_memory/test/jido_memory/examples_integration_test.exs).
