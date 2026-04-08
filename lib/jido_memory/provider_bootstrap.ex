defmodule Jido.Memory.ProviderBootstrap do
  @moduledoc """
  Caller-owned bootstrap helpers for providers that need supervised processes.

  The bootstrap contract is intentionally light:

  - providers may export `child_specs/1`
  - callers own supervision and startup strategy
  - core runtime never starts provider infrastructure implicitly
  """

  alias Jido.Memory.{ProviderInfo, ProviderRef}

  @type provider_input :: ProviderRef.t() | module() | atom() | {module() | atom(), keyword()} | nil

  @doc "Returns provider child specs when the provider exports `child_specs/1`."
  @spec child_specs(provider_input(), keyword()) ::
          {:ok, [Supervisor.child_spec()]} | {:error, term()}
  def child_specs(provider_input, opts \\ []) when is_list(opts) do
    with {:ok, provider_ref} <- normalize_provider(provider_input, opts) do
      describe_child_specs(provider_ref)
    end
  end

  @doc "Returns provider bootstrap metadata without starting any processes."
  @spec describe(provider_input(), keyword()) ::
          {:ok,
           %{
             provider: module(),
             opts: keyword(),
             child_specs: [Supervisor.child_spec()],
             provider_info: ProviderInfo.t(),
             ownership: :caller
           }}
          | {:error, term()}
  def describe(provider_input, opts \\ []) when is_list(opts) do
    with {:ok, provider_ref} <- normalize_provider(provider_input, opts),
         {:ok, child_specs} <- describe_child_specs(provider_ref),
         {:ok, provider_info} <- provider_ref.module.info(provider_ref.opts, :all) do
      {:ok,
       %{
         provider: provider_ref.module,
         opts: provider_ref.opts,
         child_specs: child_specs,
         provider_info: provider_info,
         ownership: :caller
       }}
    end
  end

  @doc "Returns true when the provider exports `child_specs/1`."
  @spec bootstrappable?(provider_input()) :: boolean()
  def bootstrappable?(provider_input) do
    case ProviderRef.normalize(provider_input) do
      {:ok, provider_ref} -> function_exported?(provider_ref.module, :child_specs, 1)
      {:error, _reason} -> false
    end
  end

  defp normalize_provider(provider_input, opts) do
    with {:ok, provider_ref} <- ProviderRef.normalize(provider_input),
         merged_opts <- Keyword.merge(provider_ref.opts, opts),
         {:ok, provider_ref} <- ProviderRef.validate(%{provider_ref | opts: merged_opts}) do
      {:ok, provider_ref}
    end
  end

  defp describe_child_specs(%ProviderRef{module: provider, opts: provider_opts}) do
    cond do
      function_exported?(provider, :child_specs, 1) ->
        case provider.child_specs(provider_opts) do
          specs when is_list(specs) -> {:ok, specs}
          other -> {:error, {:invalid_child_specs, other}}
        end

      true ->
        {:ok, []}
    end
  end
end
