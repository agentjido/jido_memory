defmodule JidoMemory.Test.MockRedis do
  @moduledoc """
  Agent-backed Redis mock for testing `Jido.Memory.Store.Redis` without a real
  Redis instance.

  It supports the subset of commands used by the store adapter:

  - `PING`
  - `SET`
  - `GET`
  - `DEL`
  - `SADD`
  - `SREM`
  - `SMEMBERS`
  - `ZADD`
  - `ZREM`
  - `ZRANGEBYSCORE`
  """

  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end)
  end

  @spec command_fn(pid()) :: (list() -> {:ok, term()} | {:error, term()})
  def command_fn(pid) do
    fn args -> command(pid, args) end
  end

  @spec command(pid(), [term()]) :: {:ok, term()} | {:error, term()}
  def command(pid, ["PING"]) do
    if Process.alive?(pid), do: {:ok, "PONG"}, else: {:error, :not_connected}
  end

  def command(pid, ["SET", key, value | rest]) do
    expires_at = parse_px_expiry(rest)

    Agent.update(pid, fn state ->
      state
      |> Map.put({:value, key}, value)
      |> maybe_put_expiry(key, expires_at)
    end)

    {:ok, "OK"}
  end

  def command(pid, ["GET", key]) do
    {:ok,
     Agent.get_and_update(pid, fn state ->
       {value, next_state} = fetch_value(state, key)
       {value, next_state}
     end)}
  end

  def command(pid, ["DEL" | keys]) do
    count =
      Agent.get_and_update(pid, fn state ->
        {deleted, next_state} =
          Enum.reduce(keys, {0, state}, fn key, {count, acc} ->
            exists? =
              Map.has_key?(acc, {:value, key}) or
                Map.has_key?(acc, {:set, key}) or
                Map.has_key?(acc, {:zset, key})

            updated =
              acc
              |> Map.delete({:value, key})
              |> Map.delete({:set, key})
              |> Map.delete({:zset, key})
              |> Map.delete({:expiry, key})

            {if(exists?, do: count + 1, else: count), updated}
          end)

        {deleted, next_state}
      end)

    {:ok, count}
  end

  def command(pid, ["SADD", key, member]) do
    Agent.update(pid, fn state ->
      members = Map.get(state, {:set, key}, MapSet.new())
      Map.put(state, {:set, key}, MapSet.put(members, member))
    end)

    {:ok, 1}
  end

  def command(pid, ["SREM", key, member]) do
    Agent.update(pid, fn state ->
      case Map.get(state, {:set, key}) do
        nil ->
          state

        members ->
          updated = MapSet.delete(members, member)

          if MapSet.size(updated) == 0 do
            Map.delete(state, {:set, key})
          else
            Map.put(state, {:set, key}, updated)
          end
      end
    end)

    {:ok, 1}
  end

  def command(pid, ["SMEMBERS", key]) do
    {:ok,
     Agent.get(pid, fn state ->
       state
       |> Map.get({:set, key}, MapSet.new())
       |> MapSet.to_list()
     end)}
  end

  def command(pid, ["ZADD", key, score, member]) do
    Agent.update(pid, fn state ->
      values = Map.get(state, {:zset, key}, %{})
      Map.put(state, {:zset, key}, Map.put(values, member, normalize_score(score)))
    end)

    {:ok, 1}
  end

  def command(pid, ["ZREM", key, member]) do
    Agent.update(pid, fn state ->
      case Map.get(state, {:zset, key}) do
        nil ->
          state

        values ->
          updated = Map.delete(values, member)

          if map_size(updated) == 0 do
            Map.delete(state, {:zset, key})
          else
            Map.put(state, {:zset, key}, updated)
          end
      end
    end)

    {:ok, 1}
  end

  def command(pid, ["ZRANGEBYSCORE", key, min, max]) do
    {:ok,
     Agent.get(pid, fn state ->
       key
       |> zset_members(state)
       |> Enum.filter(fn {_member, score} ->
         score_in_range?(score, min, max)
       end)
       |> Enum.sort_by(fn {member, score} -> {score, member} end)
       |> Enum.map(fn {member, _score} -> member end)
     end)}
  end

  def command(_pid, _args), do: {:error, :unknown_command}

  defp fetch_value(state, key) do
    if expired_key?(state, key) do
      {nil, drop_key(state, key)}
    else
      {Map.get(state, {:value, key}), state}
    end
  end

  defp drop_key(state, key) do
    state
    |> Map.delete({:value, key})
    |> Map.delete({:expiry, key})
  end

  defp expired_key?(state, key) do
    case Map.get(state, {:expiry, key}) do
      nil -> false
      expires_at when is_integer(expires_at) -> expires_at <= System.system_time(:millisecond)
    end
  end

  defp maybe_put_expiry(state, _key, nil), do: state
  defp maybe_put_expiry(state, key, expires_at), do: Map.put(state, {:expiry, key}, expires_at)

  defp parse_px_expiry(["PX", ttl]) do
    System.system_time(:millisecond) + String.to_integer(to_string(ttl))
  end

  defp parse_px_expiry(_rest), do: nil

  defp normalize_score(score) when is_integer(score), do: score
  defp normalize_score(score) when is_binary(score), do: String.to_integer(score)

  defp zset_members(key, state) do
    state
    |> Map.get({:zset, key}, %{})
    |> Enum.to_list()
  end

  defp score_in_range?(_score, "-inf", "+inf"), do: true
  defp score_in_range?(score, "-inf", max), do: score <= normalize_bound(max)
  defp score_in_range?(score, min, "+inf"), do: score >= normalize_bound(min)
  defp score_in_range?(score, min, max), do: score >= normalize_bound(min) and score <= normalize_bound(max)

  defp normalize_bound(bound) when is_integer(bound), do: bound
  defp normalize_bound(bound) when is_binary(bound), do: String.to_integer(bound)
end
