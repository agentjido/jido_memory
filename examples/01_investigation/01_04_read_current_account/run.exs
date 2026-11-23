Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.ReadCurrentAccount do
  @moduledoc false
  alias Jido.Joi

  use Jido.Flow,
    name: "read_current_account",
    schema: Joi.object(%{account_key: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  alias ReqLLM.Context
  alias SupportDesk.Inference

  flow do
    step("read_account",
      action: JidoMemory.Examples.Ash.Accounts.Jido.ReadAccount,
      params: %{account_key: input(:account_key)}
    )

    step "answer", [read <- result("read_account"), inference <- context(:inference)] do
      account = read.result
      evidence = Map.take(account, [:account_key, :refund_eligible, :revision])
      line = evidence_line(evidence)

      {answer, call} =
        Inference.call!(inference, [
          Context.system("Copy the account evidence line exactly. Output only that line."),
          Context.user("Can this account receive a refund?\nAccount evidence:\n#{line}")
        ])

      {:ok, %{decision: :allowed, evidence: evidence, answer: answer, call: call}}
    end

    output(%{trace: result("answer")})
  end

  def evidence_line(evidence) do
    eligibility = if evidence.refund_eligible, do: "eligible", else: "ineligible"
    "[#{evidence.account_key} rev #{evidence.revision}] The account is #{eligibility} for a refund."
  end
end

defmodule SupportDesk.CurrentAccountAgent do
  @moduledoc false

  use Jido.Agent, name: "current_account_agent"

  routes do
    signal_source("/examples/memory/current-account")

    route "examples.memory.account.read", SupportDesk.ReadCurrentAccount, as: :read do
      state(:unchanged)
      reply("examples.memory.account.answer", from: output(:trace))
    end
  end
end

defmodule SupportDesk.CurrentAccountExample do
  @moduledoc false

  alias JidoMemory.Examples.Ash.Account
  alias SupportDesk.CurrentAccountAgent, as: Agent
  alias SupportDesk.{Inference, ReadCurrentAccount}

  def run(argv) do
    inference = Inference.from_args!(argv, &fixture/3)
    north = create_account!("north", true, "north reconciliation note")
    _south = create_account!("south", false, "south reconciliation note")

    agent = Agent.instantiate!(id: "account-support")
    request = Agent.read_signal!(%{account_key: "AC-17"})
    north_first = read!(agent, request, "north", inference)
    south = read!(agent, request, "south", inference)

    Ash.update!(north, %{refund_eligible: false, revision: 2}, actor: %{role: :admin}, tenant: "north")
    north_latest = read!(agent, request, "north", inference)

    forbidden = %{ash: %{tenant: "north", actor: %{role: :visitor}}, inference: inference}

    {:error, %{details: %{reason: :forbidden}}} =
      Agent.cmd(agent, request, context: forbidden)

    traces = %{
      north_first: north_first,
      south: south,
      north_latest: north_latest,
      denied: %{decision: :forbidden, model_calls: 0}
    }

    json = Jason.encode!(traces, pretty: true)
    IO.puts(json)

    assert_evidence!(north_first, true, 1)
    assert_evidence!(south, false, 1)
    assert_evidence!(north_latest, false, 2)
    false = String.contains?(json, ["north reconciliation note", "south reconciliation note"])
  end

  defp create_account!(tenant, eligible, note) do
    attrs = %{account_key: "AC-17", refund_eligible: eligible, revision: 1, internal_note: note}
    Ash.create!(Account, attrs, actor: %{role: :admin}, tenant: tenant)
  end

  defp read!(agent, request, tenant, inference) do
    context = %{ash: %{tenant: tenant, actor: %{role: :support}}, inference: inference}
    {:ok, _, [%{signal: reply}]} = Agent.cmd(agent, request, context: context)
    Map.put(reply.data, :tenant, tenant)
  end

  defp fixture(model, prompt, _options) do
    %{content: [%{text: text}]} = List.last(prompt.messages)
    [_, line] = String.split(text, "\nAccount evidence:\n", parts: 2)
    Inference.fixture_reply(model, prompt, line)
  end

  defp assert_evidence!(trace, eligible, revision) do
    %{evidence: %{account_key: "AC-17", refund_eligible: ^eligible, revision: ^revision} = evidence} = trace
    3 = map_size(evidence)
    expected = ReadCurrentAccount.evidence_line(evidence)
    ^expected = String.trim(trace.answer)
    [%{role: :system}, %{role: :user, content: content}] = trace.call.model_input
    true = String.ends_with?(content, expected)
  end
end

SupportDesk.CurrentAccountExample.run(System.argv())
