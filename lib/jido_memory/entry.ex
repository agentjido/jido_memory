defmodule Jido.Memory.Entry do
  @moduledoc false

  @doc false
  @spec validate(term()) :: :ok | {:error, :invalid_record | :invalid_key}
  def validate(%{key: key, value: value, source_signal_id: source_id}) when is_map(value) and is_binary(source_id),
    do: validate_key(key)

  def validate(_record), do: {:error, :invalid_record}

  @doc false
  @spec validate_key(term()) :: :ok | {:error, :invalid_key}
  def validate_key(key) when is_binary(key) and byte_size(key) in 1..256 do
    if String.valid?(key), do: :ok, else: {:error, :invalid_key}
  end

  def validate_key(_key), do: {:error, :invalid_key}
end
