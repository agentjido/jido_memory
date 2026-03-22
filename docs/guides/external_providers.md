# External Providers

`jido_memory` ships built-in `:basic` and `:tiered` providers, but the provider
contract is intentionally open so other libraries can plug in their own memory
implementation.

External-provider interop is opt-in:

- direct provider modules work without registration
- direct `{module, opts}` tuples work without registration
- alias-based selection is helper-only through `provider_aliases`

## Provider Contract

An external provider implements `Jido.Memory.Provider`.

Required callbacks:

- `validate_config/1`
- `child_specs/1`
- `init/1`
- `capabilities/1`
- `remember/3`
- `get/3`
- `retrieve/3`
- `forget/3`
- `prune/2`
- `info/2`

Optional advanced behaviors stay separate from the core provider contract:

- `Jido.Memory.Capability.Lifecycle`
- `Jido.Memory.Capability.ExplainableRetrieval`
- `Jido.Memory.Capability.Operations`
- `Jido.Memory.Capability.Governance`
- `Jido.Memory.Capability.TurnHooks`

That separation lets an external provider implement only the surfaces it
actually supports while the common runtime continues to return
compatibility-safe unsupported-capability errors for callers using the shared
API.

## Selection Options

### Direct Module

```elixir
{Jido.Memory.Plugin,
 %{
   provider: MyApp.Memory.ExternalProvider,
   provider_opts: [store: {Jido.Memory.Store.ETS, [table: :external_memory]}]
 }}
```

### Direct Tuple

```elixir
{Jido.Memory.Plugin,
 %{
   provider:
     {MyApp.Memory.ExternalProvider,
      [store: {Jido.Memory.Store.ETS, [table: :external_memory]}}}
 }}
```

### Alias With `provider_aliases`

```elixir
aliases = %{external_demo: MyApp.Memory.ExternalProvider}

{Jido.Memory.Plugin,
 %{
   provider: :external_demo,
   provider_aliases: aliases,
   provider_opts: [store: {Jido.Memory.Store.ETS, [table: :external_memory]}]
 }}
```

Alias selection is optional and local to the runtime or plugin call path.
External packages can expose a helper such as `MyApp.Memory.provider_aliases/0`,
but `jido_memory` does not require a global registry.

Example:
- `/Users/Pascal/code/agentjido/jido_memory/examples/external_provider_agent.exs`

## Bootstrap Ownership

External providers that need supervised runtime processes should expose them via
`child_specs/1`.

`Jido.Memory.Runtime` and `Jido.Memory.Plugin` stay process-neutral. They do not
start provider processes automatically. Applications own bootstrap:

```elixir
provider = {MyApp.Memory.ExternalProvider, [repo: MyApp.Repo]}

{:ok, child_specs} = Jido.Memory.ProviderBootstrap.child_specs(provider)

children = [
  {Task.Supervisor, name: MyApp.TaskSupervisor}
] ++ child_specs
```

You can also inspect the effective bootstrap contract:

```elixir
{:ok, bootstrap} = Jido.Memory.ProviderBootstrap.describe(provider)
```

## Error Normalization

Providers can return their own internal errors, but callers using the common
runtime should still see compatibility-safe results.

Practical guidance:

- use deterministic config validation in `validate_config/1`
- return unsupported-capability behavior through the optional capability gates
- avoid leaking provider-internal bootstrap details through the common runtime

The shared runtime already normalizes invalid providers and unsupported
capabilities into tuple-style public results.

## `jido_memory_os` Boundary

`jido_memory_os` is one candidate external provider library, but it is not a
built-in dependency of `jido_memory`.

Choose built-in `:tiered` when you want the standard short/mid/long memory model
inside the core package.

Choose `jido_memory_os` when you need its native advanced workflows, such as:

- manager-driven orchestration
- journaling and replay
- approvals and governance
- framework-specific plugin flows

If `jido_memory_os` later exposes a canonical provider module again, it should
plug into the same external-provider seam documented here rather than changing
the built-in provider defaults.

## Current Open Questions

The interop seam is implemented, but a few deliberate follow-ons remain:

- whether helper-only alias registration is sufficient or should gain optional app-level config
- how much provider-bootstrap guidance should move into release-grade examples
- whether a reference external provider package should ship alongside the contract
