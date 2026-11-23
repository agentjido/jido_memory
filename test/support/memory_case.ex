defmodule Jido.Memory.Testing.MemoryCase do
  @moduledoc """
  Runs the same memory contract through an Agent for each storage binding.

  Use `fixture: YourFixture`. The fixture opens an isolated session per test
  and registers cleanup with ExUnit. Mutations return only after the Agent state
  commits or the external store acknowledges the operation. Recall returns the
  records from the Agent's reply. Restart opens a fresh Agent in the same scope.
  """

  use ExUnit.CaseTemplate

  @type session :: term()
  @type memory_record :: %{key: String.t(), value: map(), source_signal_id: String.t()}

  @callback open(ExUnit.Callbacks.context(), :primary | :secondary) :: {:ok, session()} | {:error, term()}
  @callback remember(session(), String.t(), map()) :: {:ok, session(), String.t()} | {:error, term()}
  @callback recall(session(), keyword()) :: {:ok, [memory_record()]} | {:error, term()}
  @callback forget(session(), String.t()) :: {:ok, session()} | {:error, term()}
  @callback restart(session()) :: {:ok, session()} | {:error, term()}

  using opts do
    fixture = Keyword.fetch!(opts, :fixture)

    quote do
      @memory_fixture unquote(fixture)

      setup context do
        assert {:ok, memory} = @memory_fixture.open(context, :primary)
        {:ok, memory: memory}
      end

      test "a record retains its source and stays forgotten after restart", %{memory: memory} do
        value = %{issue: "duplicate_charge", summary: "Refunded the second charge"}

        assert {:ok, memory, source_id} = @memory_fixture.remember(memory, "T-17", value)
        assert is_binary(source_id) and byte_size(source_id) > 0
        assert {:ok, memory} = @memory_fixture.restart(memory)

        assert {:ok, [%{key: "T-17", value: ^value, source_signal_id: ^source_id}]} =
                 @memory_fixture.recall(memory, where: %{issue: "duplicate_charge"}, limit: 3)

        assert {:ok, memory} = @memory_fixture.forget(memory, "T-17")
        assert {:ok, memory} = @memory_fixture.forget(memory, "T-17")
        assert {:ok, memory} = @memory_fixture.restart(memory)
        assert {:ok, []} = @memory_fixture.recall(memory, limit: 3)
      end

      test "an upsert replaces the value and makes it the most recent match", %{memory: memory} do
        original = %{issue: "duplicate_charge", summary: "Refund requested"}
        corrected = %{original | summary: "Refund confirmed"}
        unrelated = %{issue: "delivery_delay", summary: "Carrier contacted"}

        assert {:ok, memory, _} = @memory_fixture.remember(memory, "T-17", original)
        assert {:ok, memory, _} = @memory_fixture.remember(memory, "T-18", original)
        assert {:ok, memory, source_id} = @memory_fixture.remember(memory, "T-17", corrected)
        assert {:ok, memory, _} = @memory_fixture.remember(memory, "T-19", unrelated)

        assert {:ok, [%{key: "T-17", value: ^corrected, source_signal_id: ^source_id}]} =
                 @memory_fixture.recall(memory, where: %{issue: "duplicate_charge"}, limit: 1)

        assert {:ok, [%{key: "T-17"}, %{key: "T-18"}]} =
                 @memory_fixture.recall(memory, where: %{issue: "duplicate_charge"}, limit: 4)
      end

      test "scopes can store and forget the same key independently", %{memory: primary} = context do
        assert {:ok, secondary} = @memory_fixture.open(context, :secondary)
        first = %{issue: "duplicate_charge", summary: "Refund confirmed"}
        second = %{first | summary: "Investigation open"}

        assert {:ok, primary, _} = @memory_fixture.remember(primary, "T-17", first)
        assert {:ok, []} = @memory_fixture.recall(secondary, limit: 3)
        assert {:ok, secondary, _} = @memory_fixture.remember(secondary, "T-17", second)
        assert {:ok, [%{key: "T-17", value: ^first}]} = @memory_fixture.recall(primary, limit: 3)
        assert {:ok, primary} = @memory_fixture.forget(primary, "T-17")
        assert {:ok, []} = @memory_fixture.recall(primary, limit: 3)
        assert {:ok, [%{key: "T-17", value: ^second}]} = @memory_fixture.recall(secondary, limit: 3)
      end

      test "an invalid write keeps the last valid value", %{memory: memory} do
        value = %{issue: "duplicate_charge", summary: "Refund confirmed"}

        assert {:ok, memory, source_id} = @memory_fixture.remember(memory, "T-17", value)
        assert {:error, _} = @memory_fixture.remember(memory, "T-17", %{value | summary: 42})

        assert {:ok, [%{key: "T-17", value: ^value, source_signal_id: ^source_id}]} =
                 @memory_fixture.recall(memory, limit: 3)
      end

      test "recall rejects unknown filter fields and invalid limits", %{memory: memory} do
        assert {:error, _} = @memory_fixture.recall(memory, where: %{unknown_field: "value"}, limit: 3)
        assert {:error, _} = @memory_fixture.recall(memory, limit: 0)
      end
    end
  end
end
