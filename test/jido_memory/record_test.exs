defmodule Jido.Memory.RecordTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Record

  test "builds records with deterministic ids and normalized fields" do
    now = 1_700_000_000_000

    assert {:ok, %Record{} = record} =
             Record.new(
               %{
                 namespace: :agent_test,
                 class: "semantic",
                 kind: "fact",
                 text: "stored text",
                 tags: ["alpha", :beta, "alpha"],
                 source: " source ",
                 observed_at: now,
                 metadata: %{topic: "memory"},
                 version: 2
               },
               now: now
             )

    assert record.id =~ "mem_"
    assert record.namespace == "agent_test"
    assert record.class == :semantic
    assert record.kind == "fact"
    assert record.tags == ["alpha", "beta"]
    assert record.source == "source"
    assert record.observed_at == now
    assert record.version == 2
    assert Record.stable_id(Map.from_struct(record)) == record.id
  end

  test "respects explicit ids and normalizes timestamps and text values" do
    now = 1_700_000_000_000
    dt = DateTime.from_unix!(now, :millisecond)
    naive = DateTime.to_naive(dt)

    assert {:ok, %Record{} = record} =
             Record.new(
               %{
                 id: " explicit-id ",
                 namespace: "agent:test",
                 class: :episodic,
                 kind: :event,
                 text: 123,
                 observed_at: dt,
                 expires_at: naive,
                 source: ""
               },
               now: now
             )

    assert record.id == "explicit-id"
    assert record.text == "123"
    assert record.observed_at == now
    assert record.expires_at == now
    assert record.source == nil
  end

  test "canonical_classes and kind helpers expose normalized values" do
    assert Record.canonical_classes() == [:episodic, :semantic, :procedural, :working]
    assert {:ok, :working} = Record.normalize_class("working")
    assert {:ok, :event} = Record.normalize_kind(:event)
    assert {:ok, "fact"} = Record.normalize_kind(" fact ")
    assert Record.kind_key(:fact) == "fact"
    assert Record.kind_key("fact") == "fact"
    assert Record.kind_key({:custom, 1}) == "{:custom, 1}"
  end

  test "normalize_tags handles nil and validation failures" do
    assert {:ok, []} = Record.normalize_tags(nil)
    assert {:error, :empty_tag} = Record.normalize_tags([""])
    assert {:error, {:invalid_tag, 123}} = Record.normalize_tags([123])
    assert {:error, {:invalid_tags, :bad}} = Record.normalize_tags(:bad)
  end

  test "new validates namespace class kind id timestamps and metadata" do
    assert {:error, :namespace_required} = Record.new(%{class: :semantic, observed_at: 1})
    assert {:error, {:invalid_namespace, 123}} = Record.new(%{namespace: 123, class: :semantic, observed_at: 1})

    assert {:error, {:invalid_class, "unknown"}} =
             Record.new(%{namespace: "agent:test", class: "unknown", observed_at: 1})

    assert {:error, {:invalid_kind, ""}} =
             Record.new(%{namespace: "agent:test", class: :semantic, kind: "", observed_at: 1})

    assert {:error, :invalid_id} = Record.new(%{id: " ", namespace: "agent:test", class: :semantic, observed_at: 1})

    assert {:error, {:invalid_id, 123}} =
             Record.new(%{id: 123, namespace: "agent:test", class: :semantic, observed_at: 1})

    assert {:error, {:invalid_timestamp, :bad}} =
             Record.new(%{namespace: "agent:test", class: :semantic, observed_at: :bad})

    assert {:error, {:invalid_timestamp, :bad}} =
             Record.new(%{namespace: "agent:test", class: :semantic, observed_at: 1, expires_at: :bad})

    assert {:error, {:invalid_string, 123}} =
             Record.new(%{namespace: "agent:test", class: :semantic, observed_at: 1, source: 123})

    assert {:error, {:invalid_map, :bad}} =
             Record.new(%{namespace: "agent:test", class: :semantic, observed_at: 1, metadata: :bad})

    assert_raise ArgumentError, ~r/invalid memory record/, fn -> Record.new!(%{namespace: nil}) end
  end

  test "new rejects invalid top-level attrs input" do
    assert {:error, :invalid_attrs} = Record.new(:bad)
  end

  test "normalize_version falls back and blank text becomes nil" do
    assert {:ok, %Record{version: 1, text: nil}} =
             Record.new(%{
               namespace: "agent:test",
               class: :semantic,
               observed_at: 1,
               version: -1,
               text: "   "
             })
  end
end
