# Provider Selection

This guide explains how `jido_memory` decides which provider backs a given
memory call.

Use it when you need to understand:

- built-in versus external provider selection
- precedence between runtime overrides, request attrs, and plugin state
- alias-based provider selection
- what stays stable across provider changes

## Core Rule

Provider selection is explicit and config-driven.

`jido_memory` does not auto-pick a provider per query. The shared plugin and
runtime resolve one effective provider for the call, then dispatch through that
provider.

After selection, the chosen provider may still route internally:

- `:tiered` can route across short, mid, and long memory surfaces
- `:mem0` can route extraction, reconciliation, and scoped retrieval behavior internally
- `:mirix` can route across its own memory types

That internal routing happens inside the selected provider, not at the shared
runtime level.

## Resolution Order

The effective provider is resolved in this order:

1. runtime opts such as `provider: :mirix`
2. request attrs that include `provider`
3. plugin state from `Jido.Memory.Plugin`
4. the default built-in provider, `:basic`

This is the same precedence used by the runtime and the provider-aware plugin
path.

## Supported Selection Inputs

You can select a provider with:

- built-in aliases: `:basic`, `:tiered`, `:mem0`, `:mirix`
- direct modules such as `Jido.Memory.Provider.Mem0` or `Jido.Memory.Provider.Mirix`
- `{module, opts}` tuples
- external aliases supplied through `provider_aliases`

Examples:

```elixir
provider: :basic
```

```elixir
provider: Jido.Memory.Provider.Tiered
```

```elixir
provider:
  {Jido.Memory.Provider.Mem0,
   [
     store: {Jido.Memory.Store.ETS, [table: :agent_mem0_memory]},
     namespace: "agent:mem0"
   ]}
```

```elixir
provider:
  {Jido.Memory.Provider.Mirix,
   [
     core_store: {Jido.Memory.Store.ETS, [table: :agent_core_memory]}
   ]}
```

```elixir
provider: :external_demo,
provider_aliases: %{external_demo: MyApp.Memory.ExternalProvider}
```

## Plugin Configuration

For most agents, provider choice is set when `Jido.Memory.Plugin` mounts.

```elixir
{Jido.Memory.Plugin,
 %{
   provider: :tiered,
   provider_opts: [
     short_store: {Jido.Memory.Store.ETS, [table: :agent_short_memory]},
     mid_store: {Jido.Memory.Store.ETS, [table: :agent_mid_memory]}
   ]
 }}
```

That provider is then stored in plugin state and reused by later action and
runtime calls unless something more specific overrides it.

## Runtime Overrides

Shared runtime calls can override the plugin-selected provider explicitly.

```elixir
Jido.Memory.Runtime.retrieve(
  agent,
  %{text_contains: "deployment"},
  provider: :mirix
)
```

That is useful for:

- testing
- migration experiments
- one-off tooling or scripts

It is not the same as automatic provider choice by the agent. The caller is
still making the decision explicitly.

## Request-Level Provider Attrs

Request attrs can also carry provider selection when the caller uses the shared
action or runtime path and does not pass a runtime override.

That path exists mainly for compatibility and explicit dispatch cases. In
general, plugin config or runtime opts are easier to reason about than embedding
provider choice in every request payload.

## Default Fallback

If no provider is selected through runtime opts, request attrs, or plugin state,
`jido_memory` falls back to the built-in `:basic` provider.

That keeps existing ETS-style usage simple and preserves the compatibility path
for callers that do not opt into a more advanced provider.

## Alias Notes

Built-in aliases are always available:

- `:basic`
- `:tiered`
- `:mem0`
- `:mirix`

External aliases are helper-only and local to the call or plugin config that
provides them through `provider_aliases`.

There is no required global registry for external providers.

## What Stays Stable

Changing providers does not require changing the shared agent-facing core memory
surface:

- `Jido.Memory.Plugin`
- `Jido.Memory.Runtime`
- `memory.remember`
- `memory.retrieve`
- `memory.recall`
- `memory.forget`

What can change is the behavior behind that surface:

- available capabilities
- explainability richness
- lifecycle support
- scoped identity and provider-direct maintenance workflows
- provider-direct advanced APIs such as MIRIX ingest or vault workflows

## Related Guides

- [Built-In Providers](/Users/Pascal/code/agentjido/jido_memory/docs/guides/built_in_providers.md)
- [External Providers](/Users/Pascal/code/agentjido/jido_memory/docs/guides/external_providers.md)
- [Follow-On Acceptance Matrix](/Users/Pascal/code/agentjido/jido_memory/docs/guides/follow_on_acceptance_matrix.md)
