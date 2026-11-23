Code.require_file("../../support/resolution_agent.exs", __DIR__)

{agent, signal} = SupportDesk.seed_resolution!()
value = signal.data.value
source_id = signal.id

{:ok, [%{key: "T-17", value: ^value, source_signal_id: ^source_id} = resolution]} =
  Jido.Memory.recall(agent, :resolutions, where: %{issue: "duplicate_charge"}, limit: 1)

IO.inspect(resolution, label: "Recalled resolution")
