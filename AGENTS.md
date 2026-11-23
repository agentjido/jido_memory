# Instructions for Jido Memory

This branch develops Jido Memory 2 for Jido v3. Use the previous Jido Memory
1.x source for changes to the v2 provider API.

- Use `Jido.Memory.Plugin` for Agent state, read grants, and named memory
  targets. Keep Spark declarations and translation in `Jido.Memory.DSL`.
- Use `Jido.Joi` for collection value schemas. Change state-backed memory
  with Directives and apply changes with the Agent Turn.
- Keep external collection writes in the host application. Store adapters
  apply scope and filters before they limit results.
- Keep optional backend dependencies in the example projects unless the
  package contract requires them.
- Add public API docs and types. Use Conventional Commits. The release
  tooling generates `CHANGELOG.md`.

## Verify a change

```sh
mix setup
mix format --check-formatted
mix test
mix coveralls.html
mix credo --strict
mix doctor --raise
mix docs -f html -f markdown
```

Use `mix quality` to run the quality checks with Dialyzer. Aim for more than
90% line coverage. Run the affected examples from the [examples ladder](docs/examples-ladder.md).
