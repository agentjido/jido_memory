defmodule Jido.Memory.ProviderBootstrap do
  @moduledoc """
  Caller-owned bootstrap helpers for providers that need runtime processes.

  `Jido.Memory.Runtime` and `Jido.Memory.Plugin` stay process-neutral. They do
  not start provider-owned processes automatically.

  Providers that need supervision should expose those requirements through
  `child_specs/1`. Applications can then inspect and start those children under
  their own supervisor.
  """

  alias Jido.Memory.ProviderRef

  @type provider_input :: ProviderRef.t() | module() | {module(), keyword()} | nil

  @spec child_specs(provider_input(), keyword()) :: {:ok, [Supervisor.child_spec()]} | {:error, term()}
  def child_specs(provider, overrides \\ []) when is_list(overrides) do
    with {:ok, provider_ref} <- normalize_provider(provider, overrides) do
      {:ok, provider_ref.module.child_specs(provider_ref.opts)}
    end
  end

  @spec describe(provider_input(), keyword()) :: {:ok, map()} | {:error, term()}
  def describe(provider, overrides \\ []) when is_list(overrides) do
    with {:ok, provider_ref} <- normalize_provider(provider, overrides),
         {:ok, provider_meta} <- provider_ref.module.init(provider_ref.opts) do
      {:ok,
       %{
         provider: provider_ref.module,
         opts: provider_ref.opts,
         child_specs: provider_ref.module.child_specs(provider_ref.opts),
         provider_meta: provider_meta,
         ownership: :caller
       }}
    end
  end

  defp normalize_provider(provider, overrides) do
    provider_aliases = Keyword.get(overrides, :provider_aliases)
    extra_opts = Keyword.drop(overrides, [:provider_aliases])

    with {:ok, provider_ref} <- ProviderRef.normalize(provider, provider_aliases) do
      {:ok, %{provider_ref | opts: Keyword.merge(provider_ref.opts, extra_opts)}}
    end
  end
end
