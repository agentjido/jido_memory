defmodule Jido.Memory.MirixPhase03IntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Provider.Mirix
  alias Jido.Memory.ProviderContract
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime

  test "mirix preserves canonical record mapping across memory types" do
    provider = ProviderFixtures.mirix_provider("phase03_mirix_mapping")
    target = %{id: "phase03-mirix-mapping-#{System.unique_integer([:positive])}"}

    for {memory_type, class} <- [
          {:core, :working},
          {:episodic, :episodic},
          {:semantic, :semantic},
          {:procedural, :procedural},
          {:resource, :working}
        ] do
      text = "phase03 mirix #{memory_type} record"

      assert {:ok, %Record{id: id, class: ^class, metadata: metadata}} =
               Runtime.remember(
                 target,
                 %{class: class, kind: :event, text: text, memory_type: memory_type},
                 provider: provider
               )

      assert get_in(metadata, ["mirix", "memory_type"]) == Atom.to_string(memory_type)

      assert {:ok, %Record{id: ^id, class: ^class, metadata: fetched_metadata}} =
               Runtime.get(target, id, provider: provider)

      assert get_in(fetched_metadata, ["mirix", "memory_type"]) == Atom.to_string(memory_type)
    end
  end

  test "mirix keeps namespaces isolated across all public memory-type stores" do
    provider = ProviderFixtures.mirix_provider("phase03_mirix_namespace")
    source_target = %{id: "phase03-mirix-source-#{System.unique_integer([:positive])}"}
    other_target = %{id: "phase03-mirix-other-#{System.unique_integer([:positive])}"}

    stored_ids =
      for {memory_type, class} <- [
            {:core, :working},
            {:episodic, :episodic},
            {:semantic, :semantic},
            {:procedural, :procedural},
            {:resource, :working}
          ] do
        assert {:ok, %Record{id: id}} =
                 Runtime.remember(
                   source_target,
                   %{class: class, kind: :event, text: "phase03 isolate #{memory_type}", memory_type: memory_type},
                   provider: provider
                 )

        id
      end

    for id <- stored_ids do
      assert {:error, :not_found} = Runtime.get(other_target, id, provider: provider)
    end

    assert {:ok, []} =
             Runtime.retrieve(
               other_target,
               %{text_contains: "phase03 isolate", classes: [:working, :episodic, :semantic, :procedural]},
               provider: provider
             )
  end

  test "mirix excludes vault records from canonical retrieval" do
    provider = ProviderFixtures.mirix_provider("phase03_mirix_vault")
    target = %{id: "phase03-mirix-vault-#{System.unique_integer([:positive])}"}

    assert {:ok, %Record{id: public_id}} =
             Runtime.remember(
               target,
               %{class: :semantic, kind: :fact, text: "phase03 visible semantic memory"},
               provider: provider
             )

    assert {:ok, %Record{id: vault_id, metadata: metadata}} =
             Mirix.put_vault_entry(
               target,
               %{kind: :credential, text: "phase03 vault secret"},
               provider: provider
             )

    assert get_in(metadata, ["mirix", "memory_type"]) == "vault"

    assert {:ok, [%Record{id: ^public_id}]} =
             Runtime.retrieve(target, %{text_contains: "phase03", order: :asc}, provider: provider)

    assert {:ok, explanation} =
             Runtime.explain_retrieval(target, %{text_contains: "phase03"}, provider: provider)

    refute Enum.any?(explanation.results, &(&1.id == vault_id))
    assert {:ok, %Record{id: ^vault_id}} = Mirix.get_vault_entry(target, vault_id, provider: provider)
  end

  test "mirix passes the canonical provider contract through the built-in alias" do
    provider = ProviderFixtures.mirix_provider("phase03_mirix_contract")
    target = %{id: "phase03-mirix-contract-#{System.unique_integer([:positive])}"}

    assert {:ok, %{record: %Record{}, fetched: %Record{}, records: [%Record{}], deleted?: true}} =
             ProviderContract.exercise_core_flow(
               provider,
               target,
               %{class: :semantic, kind: :fact, text: "phase03 mirix contract flow"},
               %{text_contains: "phase03 mirix contract flow", classes: [:semantic]}
             )
  end
end
