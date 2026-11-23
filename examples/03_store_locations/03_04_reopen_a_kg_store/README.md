# Reopen a KG store without mixing scopes

The Agent's Flow calls an authorized read Action for the notes graph.
[Agent definition](run.exs)

Write the same subject and predicate to two RDF named graphs in a disposable
TripleStore database. Close and reopen it. Alice can read her preference.
Bob can read the project note. When Bob requests the private graph, the Flow
denies the read before it queries the database.

From `examples/integrations/kg`, run the offline model fixture.

```sh
mix deps.get
mix run ../../03_store_locations/03_04_reopen_a_kg_store/run.exs
```

Add `--config /path/to/reqllm.exs` after the script path to run with ReqLLM.
The JSON shows each graph that the Agent opened, its access decision, and the
exact message sent to the model. The script checks the full final message for
each request. TripleStore uses RocksDB and needs a native build toolchain.
With CMake 4, set `CMAKE_POLICY_VERSION_MINIMUM=3.5` when building RocksDB.
