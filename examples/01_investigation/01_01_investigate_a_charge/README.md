# 01_01 Investigate an ambiguous charge

The [Agent](agent.exs) declares a `:resolutions` collection. It commits two
ticket Signals before it receives a question. Its Flow offers the model one
ReqLLM tool, `recall_resolutions`. The first
lookup returns two cases. A new detail from the customer gives the model a
reason to narrow its second lookup. The tool maps charge status to an exact
memory filter.

The script runs two cases. A posted charge yields one matching ticket, which
the model cites in its reply. An unknown status yields no matches. The Flow
stops after the second lookup and asks whether both charges posted.

```sh
mix run examples/01_investigation/01_01_investigate_a_charge/run.exs
```

Append `--config /path/to/reqllm.exs` to use a live model that supports tool
calling. Use the [ReqLLM configuration](../../00_start_here/00_02_answer_from_memory/README.md#run-with-reqllm).

Each JSON trace shows the messages and tool definition for each call, the
arguments the model chose, the filter applied, the records returned, and the
reason the Flow stopped.
