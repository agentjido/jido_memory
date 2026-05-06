defmodule JidoMemory.Test.LiveRedis do
  @moduledoc false

  @default_host "127.0.0.1"
  @default_port 6379
  @default_db 15
  @default_timeout 5_000

  @spec command_fn(keyword()) :: (list() -> {:ok, term()} | {:error, term()})
  def command_fn(opts \\ []) do
    connection = connection_opts(opts)

    fn command ->
      command(connection, command)
    end
  end

  @spec ensure_ready(keyword()) :: :ok | {:error, term()}
  def ensure_ready(opts \\ []) do
    case command(connection_opts(opts), ["PING"]) do
      {:ok, "PONG"} -> :ok
      {:ok, other} -> {:error, {:unexpected_ping_reply, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec cleanup_prefix(binary(), keyword()) :: :ok | {:error, term()}
  def cleanup_prefix(prefix, opts \\ []) when is_binary(prefix) do
    connection = connection_opts(opts)
    pattern = "#{prefix}:*"

    with_connection(connection, fn socket ->
      with :ok <- select_db(socket, connection.db, connection.timeout) do
        cleanup_scan(socket, pattern, "0", connection.timeout)
      end
    end)
  end

  @spec unique_prefix(binary()) :: binary()
  def unique_prefix(base) when is_binary(base) do
    "#{base}:#{System.unique_integer([:positive, :monotonic])}"
  end

  @spec endpoint(keyword()) :: binary()
  def endpoint(opts \\ []) do
    %{host: host, port: port, db: db} = connection_opts(opts)
    "#{host}:#{port}/#{db}"
  end

  defp command(connection, redis_command) when is_list(redis_command) do
    with_connection(connection, fn socket ->
      with :ok <- select_db(socket, connection.db, connection.timeout),
           :ok <- send_command(socket, redis_command) do
        read_response(socket, connection.timeout)
      end
    end)
  end

  defp cleanup_scan(socket, pattern, cursor, timeout) do
    with :ok <- send_command(socket, ["SCAN", cursor, "MATCH", pattern, "COUNT", "100"]),
         {:ok, [next_cursor, keys]} <- read_response(socket, timeout),
         :ok <- delete_keys(socket, keys, timeout) do
      if next_cursor == "0" do
        :ok
      else
        cleanup_scan(socket, pattern, next_cursor, timeout)
      end
    end
  end

  defp delete_keys(_socket, [], _timeout), do: :ok

  defp delete_keys(socket, keys, timeout) when is_list(keys) do
    with :ok <- send_command(socket, ["DEL" | keys]),
         {:ok, _deleted} <- read_response(socket, timeout) do
      :ok
    end
  end

  defp select_db(socket, db, timeout) do
    with :ok <- send_command(socket, ["SELECT", Integer.to_string(db)]),
         {:ok, "OK"} <- read_response(socket, timeout) do
      :ok
    else
      {:ok, other} -> {:error, {:select_failed, other}}
      {:error, reason} -> {:error, {:select_failed, reason}}
    end
  end

  defp with_connection(connection, fun) do
    tcp_opts = [:binary, active: false, packet: :raw]

    case :gen_tcp.connect(String.to_charlist(connection.host), connection.port, tcp_opts, connection.timeout) do
      {:ok, socket} ->
        try do
          fun.(socket)
        after
          :gen_tcp.close(socket)
        end

      {:error, reason} ->
        {:error, {:connect_failed, reason}}
    end
  end

  defp send_command(socket, redis_command) do
    socket
    |> :gen_tcp.send(encode_command(redis_command))
    |> normalize_send_result()
  end

  defp normalize_send_result(:ok), do: :ok
  defp normalize_send_result({:error, reason}), do: {:error, {:send_failed, reason}}

  defp encode_command(redis_command) do
    args = Enum.map(redis_command, &normalize_arg/1)

    [
      "*",
      Integer.to_string(length(args)),
      "\r\n",
      Enum.map(args, fn arg ->
        ["$", Integer.to_string(byte_size(arg)), "\r\n", arg, "\r\n"]
      end)
    ]
  end

  defp normalize_arg(arg) when is_binary(arg), do: arg
  defp normalize_arg(arg) when is_integer(arg), do: Integer.to_string(arg)
  defp normalize_arg(arg) when is_float(arg), do: :erlang.float_to_binary(arg, [:compact])
  defp normalize_arg(arg) when is_atom(arg), do: Atom.to_string(arg)
  defp normalize_arg(arg) when is_list(arg), do: IO.iodata_to_binary(arg)
  defp normalize_arg(arg), do: to_string(arg)

  defp read_response(socket, timeout) do
    case :gen_tcp.recv(socket, 1, timeout) do
      {:ok, <<prefix>>} ->
        case prefix do
          ?+ -> read_simple_string(socket, timeout)
          ?- -> read_error(socket, timeout)
          ?: -> read_integer(socket, timeout)
          ?$ -> read_bulk_string(socket, timeout)
          ?* -> read_array(socket, timeout)
          other -> {:error, {:unexpected_reply_prefix, other}}
        end

      {:error, reason} ->
        {:error, {:recv_failed, reason}}
    end
  end

  defp read_simple_string(socket, timeout), do: read_line(socket, timeout)

  defp read_error(socket, timeout) do
    with {:ok, error} <- read_line(socket, timeout) do
      {:error, {:redis_error, error}}
    end
  end

  defp read_integer(socket, timeout) do
    with {:ok, line} <- read_line(socket, timeout) do
      parse_integer(line)
    end
  end

  defp read_bulk_string(socket, timeout) do
    with {:ok, line} <- read_line(socket, timeout),
         {:ok, size} <- parse_integer(line) do
      case size do
        -1 ->
          {:ok, nil}

        size when size >= 0 ->
          with {:ok, binary} <- recv_exact(socket, size, timeout),
               :ok <- consume_crlf(socket, timeout) do
            {:ok, binary}
          end
      end
    end
  end

  defp read_array(socket, timeout) do
    with {:ok, line} <- read_line(socket, timeout),
         {:ok, count} <- parse_integer(line) do
      case count do
        -1 ->
          {:ok, nil}

        0 ->
          {:ok, []}

        count when count >= 0 ->
          Enum.reduce_while(1..count, {:ok, []}, fn _, {:ok, acc} ->
            case read_response(socket, timeout) do
              {:ok, value} -> {:cont, {:ok, [value | acc]}}
              {:error, _reason} = error -> {:halt, error}
            end
          end)
          |> case do
            {:ok, values} -> {:ok, Enum.reverse(values)}
            {:error, _reason} = error -> error
          end
      end
    end
  end

  defp read_line(socket, timeout, acc \\ []) do
    case :gen_tcp.recv(socket, 1, timeout) do
      {:ok, "\r"} ->
        case :gen_tcp.recv(socket, 1, timeout) do
          {:ok, "\n"} -> {:ok, IO.iodata_to_binary(Enum.reverse(acc))}
          {:ok, other} -> {:error, {:invalid_line_terminator, other}}
          {:error, reason} -> {:error, {:recv_failed, reason}}
        end

      {:ok, byte} ->
        read_line(socket, timeout, [byte | acc])

      {:error, reason} ->
        {:error, {:recv_failed, reason}}
    end
  end

  defp recv_exact(_socket, 0, _timeout), do: {:ok, ""}

  defp recv_exact(socket, count, timeout) when count > 0 do
    case :gen_tcp.recv(socket, count, timeout) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, {:recv_failed, reason}}
    end
  end

  defp consume_crlf(socket, timeout) do
    case :gen_tcp.recv(socket, 2, timeout) do
      {:ok, "\r\n"} -> :ok
      {:ok, other} -> {:error, {:invalid_bulk_terminator, other}}
      {:error, reason} -> {:error, {:recv_failed, reason}}
    end
  end

  defp parse_integer(binary) do
    case Integer.parse(binary) do
      {integer, ""} -> {:ok, integer}
      _other -> {:error, {:invalid_integer, binary}}
    end
  end

  defp connection_opts(opts) do
    %{
      host: Keyword.get(opts, :host, System.get_env("JIDO_MEMORY_REDIS_HOST", @default_host)),
      port: Keyword.get(opts, :port, env_integer("JIDO_MEMORY_REDIS_PORT", @default_port)),
      db: Keyword.get(opts, :db, env_integer("JIDO_MEMORY_REDIS_DB", @default_db)),
      timeout: Keyword.get(opts, :timeout, @default_timeout)
    }
  end

  defp env_integer(name, default) do
    case System.get_env(name) do
      nil ->
        default

      value ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _other -> default
        end
    end
  end
end
