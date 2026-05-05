defmodule JidoMemory.Test.MockPostgres do
  @moduledoc false

  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{rows: %{}, queries: []} end)
  end

  def query_fn(pid) do
    fn repo, sql, params, repo_opts ->
      query(pid, repo, sql, params, repo_opts)
    end
  end

  def queries(pid) do
    Agent.get(pid, fn state ->
      Enum.reverse(state.queries)
    end)
  end

  defp query(pid, repo, sql, params, repo_opts) do
    normalized = normalize_sql(sql)
    query = %{repo: repo, sql: sql, normalized: normalized, params: params, repo_opts: repo_opts}

    Agent.get_and_update(pid, fn state ->
      state = %{state | queries: [query | state.queries]}
      {reply, state} = handle_query(normalized, params, state)
      {reply, state}
    end)
  end

  defp handle_query("CREATE " <> _rest, _params, state), do: {ok(), state}
  defp handle_query("SELECT 1 FROM " <> _rest, _params, state), do: {ok(), state}

  defp handle_query("INSERT INTO " <> _rest, params, state) do
    [namespace, id, class, kind, text, source, observed_at, expires_at, record] = params

    row = %{
      namespace: namespace,
      id: id,
      class: class,
      kind: kind,
      text: text,
      source: source,
      observed_at: observed_at,
      expires_at: expires_at,
      record: record
    }

    {ok(1), put_in(state.rows[{namespace, id}], row)}
  end

  defp handle_query("SELECT record FROM " <> _rest, [namespace, id], state)
       when is_binary(namespace) and is_binary(id) do
    reply =
      case Map.get(state.rows, {namespace, id}) do
        nil -> ok_rows([])
        row -> ok_rows([[row.record]])
      end

    {reply, state}
  end

  defp handle_query("SELECT record FROM " <> _rest = sql, params, state) do
    [namespace, now | rest] = params

    {filters, rest} = take_array_filter(sql, rest, "class = ANY")
    {kind_filters, rest} = take_array_filter(sql, rest, "kind = ANY")
    {since, rest} = take_scalar_filter(sql, rest, "observed_at >= ")
    {until, rest} = take_scalar_filter(sql, rest, "observed_at <= ")
    limit = if Regex.match?(~r/ LIMIT \$\d+$/, sql), do: List.last(rest), else: nil
    order = if String.contains?(sql, "ORDER BY observed_at ASC"), do: :asc, else: :desc

    rows =
      state.rows
      |> Map.values()
      |> Enum.filter(fn row ->
        row.namespace == namespace and
          active?(row, now) and
          array_filter_matches?(row.class, filters) and
          array_filter_matches?(row.kind, kind_filters) and
          time_filter_matches?(row.observed_at, since, until)
      end)
      |> sort_rows(order)
      |> maybe_limit(limit)
      |> Enum.map(&[&1.record])

    {ok_rows(rows), state}
  end

  defp handle_query("DELETE FROM " <> _rest, [namespace, id], state)
       when is_binary(namespace) and is_binary(id) do
    existed? = Map.has_key?(state.rows, {namespace, id})
    state = update_in(state.rows, &Map.delete(&1, {namespace, id}))

    {ok(if(existed?, do: 1, else: 0)), state}
  end

  defp handle_query("DELETE FROM " <> _sql, [now], state) do
    {expired, active} =
      Enum.split_with(state.rows, fn
        {_key, %{expires_at: expires_at}} when is_integer(expires_at) -> expires_at <= now
        _row -> false
      end)

    {ok(length(expired)), %{state | rows: Map.new(active)}}
  end

  defp handle_query(sql, params, state), do: {{:error, {:unexpected_sql, sql, params}}, state}

  defp take_array_filter(sql, [value | rest], marker) do
    if String.contains?(sql, marker), do: {value, rest}, else: {[], [value | rest]}
  end

  defp take_array_filter(_sql, [], _marker), do: {[], []}

  defp take_scalar_filter(sql, [value | rest], marker) do
    if String.contains?(sql, marker), do: {value, rest}, else: {nil, [value | rest]}
  end

  defp take_scalar_filter(_sql, [], _marker), do: {nil, []}

  defp active?(%{expires_at: nil}, _now), do: true
  defp active?(%{expires_at: expires_at}, now), do: expires_at > now

  defp array_filter_matches?(_value, []), do: true
  defp array_filter_matches?(value, filters), do: value in filters

  defp time_filter_matches?(observed_at, since, until) do
    (is_nil(since) or observed_at >= since) and
      (is_nil(until) or observed_at <= until)
  end

  defp sort_rows(rows, :asc), do: Enum.sort_by(rows, fn row -> {row.observed_at, row.id} end, :asc)
  defp sort_rows(rows, :desc), do: Enum.sort_by(rows, fn row -> {row.observed_at, row.id} end, :desc)

  defp maybe_limit(rows, nil), do: rows
  defp maybe_limit(rows, limit), do: Enum.take(rows, limit)

  defp ok(num_rows \\ 0), do: {:ok, %{rows: [], num_rows: num_rows}}
  defp ok_rows(rows), do: {:ok, %{rows: rows, num_rows: length(rows)}}

  defp normalize_sql(sql) do
    sql
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end
end
