# Jido.Memory

[![Hex.pm](https://img.shields.io/hexpm/v/jido_memory.svg)](https://hex.pm/packages/jido_memory)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/jido_memory/)
[![CI](https://github.com/agentjido/jido_memory/actions/workflows/ci.yml/badge.svg?branch=release%2Fv3)](https://github.com/agentjido/jido_memory/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/jido_memory.svg)](https://github.com/agentjido/jido_memory/blob/main/LICENSE)
[![Website](https://img.shields.io/badge/website-jido.run-0f172a.svg)](https://jido.run)
[![Ecosystem](https://img.shields.io/badge/ecosystem-jido.run-0ea5e9.svg)](https://jido.run/ecosystem)
[![Discord](https://img.shields.io/badge/discord-join-5865F2.svg?logo=discord&logoColor=white)](https://jido.run/discord)

`Jido.Memory` is the memory integration package for `Jido.Agent`.

This branch develops Jido Memory **2.0.0** for Jido v3. The
[upgrade guide](guides/upgrading_to_2.md) lists the API changes and legacy
provider pins.

## Jido v3 examples

Run the model example with recall enabled and disabled.

```sh
mix example.memory
```

See the [examples ladder](docs/examples-ladder.md) for the 29 ladder cases,
backend setup, and verification results. The separate
[starter example](examples/00_start_here/00_01_remember_a_resolution/README.md)
shows how to store a resolution. The
[Agent fixture](test/support/fixtures/agent_state.exs) shows the `memory` block
and the remember, recall, and forget routes.

Use the Agent's `memory` block to declare collections, model read grants,
and read-only external collections. Use native Flow steps to call Actions
that fetch or index evidence. See the
[exact-release guide example](examples/04_find_evidence/04_03_answer_for_an_exact_release/README.md)
for an Agent that fetches a Git document, indexes it in Arcana, and uses it
as evidence on a later Turn.

## Jido v2 reference

Use the [previous source and docs](https://github.com/agentjido/jido_memory/tree/09e2ddbf0a35ec54349b5c5d4f36ca369ceaa7d7) for the
Jido Memory 1.x provider API.
