defmodule Jido.Memory.Support.ExternalProvider do
  @moduledoc false

  @behaviour Jido.Memory.Provider

  alias Jido.Memory.Provider.Basic

  def validate_config(opts), do: Basic.validate_config(opts)

  def child_specs(opts) do
    id = Keyword.get(opts, :bootstrap_id, {__MODULE__, :bootstrap})

    [
      Supervisor.child_spec(
        {Agent, fn -> %{provider: __MODULE__, namespace: Keyword.get(opts, :namespace)} end},
        id: id
      )
    ]
  end

  def init(opts) do
    with {:ok, meta} <- Basic.init(opts) do
      {:ok,
       meta
       |> Map.put(:provider, __MODULE__)
       |> Map.put(:external?, true)
       |> Map.put(:bootstrap, %{ownership: :caller, child_specs: length(child_specs(opts))})}
    end
  end

  def capabilities(meta) do
    meta
    |> Basic.capabilities()
    |> Map.put(:interop, %{external: true, caller_bootstrap: true})
  end

  def remember(target, attrs, opts), do: Basic.remember(target, attrs, opts)
  def get(target, id, opts), do: Basic.get(target, id, opts)
  def retrieve(target, query, opts), do: Basic.retrieve(target, query, opts)
  def forget(target, id, opts), do: Basic.forget(target, id, opts)
  def prune(target, opts), do: Basic.prune(target, opts)
  def info(meta, fields), do: Basic.info(meta, fields)
end
