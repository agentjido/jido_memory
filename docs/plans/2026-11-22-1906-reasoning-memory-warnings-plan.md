---
title: Warn when Agent memory is missing from AI reasoning
type: implementation-plan
date: 2026-11-22
last_reviewed: 2026-11-22
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Warn when Agent memory is missing from AI reasoning

## Goal Capsule

- **Objective** Give the Agent author an actionable compiler warning when configured memory has no visible integration in the AI reasoning Flow or has a clear wiring error.
- **Means** Test real Agent compilation first. Add a Jido Memory verifier that reads the Agent definition and the explicit Flow.
- **Authority** Save and review this plan. Implement the change after the user authorizes implementation.
- **Stop conditions** Stop at the checked plan. During implementation, keep ambiguous Flow analysis advisory and continue to use Jido's existing validation and access controls.
- **Next executor** Jido Memory implementer. Start with U1.

## Product Contract

### Summary

The Agent memory DSL declares collections and access. A Jido Flow step chooses when to use them. The compiler should help the author connect the two when the same Agent defines AI reasoning. Memory remains available to Agents that use explicit Actions, an FSM, or a statechart without AI.

### Problem Frame

An Agent can declare memory and compile successfully while its reasoning Flow never reads it. A Flow can also recall records and then give `CallModel` the original context. Both mistakes are easy to miss when the Agent and Flow definitions are separate.

### Actors

- Agent authors who configure memory and choose a reasoning Flow.
- Agent authors who use memory from an FSM, a statechart, or other non-AI logic.

### Requirements

- **R1** Keep a memory-specific compiler warning off when the Agent has no AI reasoning. Keep explicit non-AI memory use valid.
- **R2** Warn at compile time when the Agent configures both memory and AI and the declared reasoning Flow has no recognized memory step. Identify the Agent and Flow and give a correction.
- **R3** Warn about clear static errors in recognized memory steps. Include a literal grant that the reasoning root cannot use, a literal filter key outside the grant, an unknown literal named memory operation, and the direct model-context bypass in the acceptance examples.
- **R4** Allow an Agent author to turn off these warnings for deliberate manual wiring or memory use outside reasoning. Preserve existing compile errors and runtime behavior. Emit at most one memory wiring warning per Agent compilation.

### Key Flows

- Standard AI use: `memory` declares a grant. The reasoning Flow projects the conversation, recalls with the grant, and sends the resulting context to the model.
- Custom evidence use: the reasoning Flow reads records, selects and formats evidence, and sends a new context to the model.
- Non-AI use: an Agent Action, FSM, or statechart reads or updates memory as part of its own work.

### Acceptance Examples

| Agent and reasoning Flow | Expected compiler result |
| --- | --- |
| Memory and an FSM or statechart route, with no AI reasoning | Quiet. Explicit memory operations still work. |
| AI reasoning with no memory declaration | Quiet. |
| Memory and AI, with only ordinary reasoning steps in the AI Flow | One warning. Add `RecallForModel`, use a named memory Action, or turn off the advisory for deliberate manual use. |
| Memory is used on another route of an AI Agent. Its reasoning Flow has no recognized memory step. | One warning by default. Quiet with the Agent-level option set to `false`. |
| `CallModel.context` reads `result("recall", :context)` | Quiet with a valid grant. |
| A context builder reads recalled records and supplies its result to `CallModel` | Quiet. |
| The single model call and the single recall step both read `result("project", :context)`. Recall feeds only a trace. | One warning on the model step. The fix is to use the recall context or the result of a context builder that uses the recall. |
| A recall step names an unavailable grant or a forbidden literal filter key | One warning with the step and literal name. Runtime grant checks still apply. |
| `Access` selects a declared operation on a source, index, or graph | Quiet. An unknown literal binding or operation produces one warning. |
| The grant, filter keys, or operation choice depend on runtime values | Leave those checks to runtime. The presence of an explicit memory Action is visible at compile time. |

### Success Criteria

The same Agent source compiles through its normal DSL entry point. Corrected definitions compile quietly. Memory-only Agents compile quietly and keep their tested behavior. Loading, instantiating, and running a compiled Agent do not repeat the warning.

### Scope Boundaries

Cover authored Agent modules and the root reasoning Flow visible in their definitions. Limit the checks to explicit Actions and result references that the verifier can read. Leave opaque Actions, tool handlers, nested Flows, dynamic dispatch, and runtime values outside the analyzer. The advisory can identify the missing visible step and point to the manual-use option for these cases. Existing access rules, backend behavior, and Flow execution stay in their owning modules.

### Key Decisions

Use compiler warnings by default. AI and memory can coexist even when the application uses memory only outside reasoning. The proposed `warn_unwired_reasoning false` option expresses that intent or acknowledges a custom integration. The Agent still selects each memory step explicitly.

### Rejected Alternatives

- A compile error would reject valid custom and write-only integrations.
- Automatic recall would make the reasoning Flow's inputs and context harder to inspect.
- A warning in a runtime callback would repeat when the Agent loads or runs its definition.

### Dependencies

Use the current Jido `3.0.0-beta.3` and Spark `2.7.10` from the lockfile. Tests use local Agent definitions and the fixture inference client. [Dependency lockfile](../../mix.lock)

### Outstanding Questions

None block the proposed first version. Expanding coverage to nested or dynamic execution is outside this plan.

### Sources

- [Jido v3 memory plan](2026-11-22-1614-jido-v3-memory-plan.md)
- [Direct recall and model call](../../examples/00_start_here/00_02_answer_from_memory/agent.exs)
- [Evidence selection and context building](../../examples/00_start_here/00_03_fit_and_check_evidence/agent.exs)
- [Memory-only resolution Agent](../../examples/support/resolution_agent.exs)

## Planning Contract

### Product Contract Preservation

Product Contract unchanged. The direct request supplies the warning behavior and the non-AI exception. This plan specifies the first set of static checks and an Agent-level option for intentional custom use.

### Current System

`Jido.Memory.Plugin.lower/2` lowers declarations into plugin data. `prepare/2` supplies `read` grants only when the bound Flow is the sole route candidate. `RecallForModel` validates the grant and filters and returns a context plus a recall trace. `Access` selects a named source, index, or graph operation. [Memory plugin](../../lib/jido_memory/plugin.ex) · [RecallForModel](../../lib/jido_memory/actions/recall_for_model.ex) · [Access](../../lib/jido_memory/actions/access.ex)

`Jido.AI.Agent.Plugin` supplies the normalized reasoning Flow and derives the AI request route. The pinned Jido build validates related definitions during compilation and when `definition/0` loads them. Spark's verifier runs during compilation. A local AI Agent probe registered a verifier through `verifiers/0`, read both plugin entries through `__jido_definition__(related?: true)`, and captured one compiler warning with its source file in `Code.with_diagnostics/1`. Calling `definition/0` emitted no second warning. [Jido Agent DSL](https://github.com/agentjido/jido/blob/v3.0.0-beta.3/lib/jido/agent/dsl.ex) · [AI plugin](https://github.com/agentjido/jido/blob/v3.0.0-beta.3/lib/jido/ai/agent/plugin.ex)

### Target System

Spark verifies the compiled Agent → the memory verifier reads both plugin entries → it inspects the canonical reasoning Flow → it emits one diagnostic or returns `:ok`. Agents without the AI plugin take the quiet path before Flow inspection.

### Key Technical Decisions

- **KTD1 · Compilation hook.** Append a `Spark.Dsl.Verifier` through `Jido.Memory.Plugin.verifiers/0`. The pinned `use Jido.Plugin` does not forward a `verifiers:` option. Keep the existing verifiers via `defoverridable verifiers: 0` and `super()`. Use Spark's persisted `:module` and the validated, related Agent definition to find normalized plugin entries by provider. For an invalid definition, leave the existing validation error in charge. Return `{:warn, {message, annotation}}` so the diagnostic includes a source file. Use the memory section annotation where available and Spark's persisted `:file` at line 1 as the fallback. Governs R1, R2, R4 and U1.
- **KTD2 · Explicit Actions and literals.** Inspect the canonical root Flow's components for `RecallForModel` and `Access`. Compare literal `grant` and `where` keys with the grants available to the reasoning root. Report a different bound root only when an actual recall step would require that grant. Check the literal `Access` kind, binding name, and operation against normalized bindings. Skip value checks for dynamic values and a recall step with literal `enabled: false`. A recognized `Access` step is evidence of memory use in reasoning. Its operation can read or write. Governs R2, R3 and U1–U2.
- **KTD3 · Direct context bypass.** Warn only when one unconditional recall step and one `CallModel` step select the same direct `ProjectConversation` context and no model input depends on a recall result. Inspect `%Jido.Flow.Ref{source: :result}` dependencies, including references through intermediate context builders. `needs` only controls ordering. An output trace that uses recall does not connect it to the model. Keep multi-call, conditional, and otherwise ambiguous cases quiet for this check. Governs R3 and U3.
- **KTD4 · Manual use and diagnostic priority.** Add `warn_unwired_reasoning false` as a compile-time `memory` section option, with a default of `true`. Read it in the verifier. Keep it out of normalized plugin data and Agent snapshots. Give a literal wiring error priority over a direct context bypass and then over a missing recognized step. For multiple errors of the same kind, report the first step by ID. Every warning identifies the affected Agent and Flow. Step warnings also name the step. Governs R2–R4 and U1–U3.

### System Boundaries and Change Surface

| Surface | Current contract | Planned change | Compatibility or risk |
| --- | --- | --- | --- |
| `Jido.Memory.Plugin` | Declares the `memory` section and owns runtime grants | Register the verifier and declare one compile-time option | Existing memory forms and runtime plugin data keep their format |
| Internal reasoning verifier | No memory wiring diagnostic | Read the compiled Agent and its canonical Flow. Classify known cases and return a Spark diagnostic. | Build environments can promote the new warnings to errors through their existing compiler policy |
| Agent DSL tests | Runtime tests include recall, filter denial, and grant isolation | Add real compile fixtures and check the relevant diagnostics and a subsequent Agent invocation | Use unique module names and fixture inference so the tests work locally |
| `Answer from memory` example README | Explains an explicit memory step | Explain the warning, the manual-use option, and the no-AI rule | Keep runnable examples as positive cases |

### Implementation Units

#### U1 · Warn only when an AI reasoning Flow lacks an explicit memory step

- **Outcome and requirements** R1, R2, R4. One warning for a valid AI Agent with configured memory and no recognized step. Other Agents compile quietly.
- **Dependencies** None.
- **Affected surfaces** The memory Plugin and section. Proposed `Jido.Memory.ReasoningVerifier` and `test/jido_memory/reasoning_verifier_test.exs`.
- **Red** Compile Agent snippets with `Code.with_diagnostics/1`. Start with a fixture that has a memory collection and a reasoning Flow with no memory Action. Give the fixture a `signal_source` so its AI reply route compiles. Expect one warning with the Agent and Flow names and a source file. Add quiet cases for AI alone, memory alone with an explicit route that uses it, direct recall, a declared `Access` operation, and manual wiring with the option set to `false`. Cover a binding-only memory declaration and the supported explicit plugin configuration form. Compile the `use Jido.AI.Agent` form and the core Agent form with the AI plugin. Check that invalid definitions still produce the existing error. Capture diagnostics when loading, instantiating, and invoking a compiled Agent to prove they stay quiet.
- **Green and refactor** Register the compile-only verifier. Gate on the two normalized providers before inspecting the root Flow. Read the option from the Spark DSL. Keep the analyzer independent of stores and inference. Make the warning state the observed omission and give a direct correction.
- **Gate and completion** Run the focused verifier test file. The missing-step test fails on the baseline and passes with the verifier. The same suite proves the no-AI and compile-only boundaries.

#### U2 · Flag literal grant and operation errors

- **Outcome and requirements** R3, R4. A visible memory step with an unusable literal name or filter produces an actionable warning.
- **Dependencies** U1 provides the real compiler test harness and action recognition.
- **Affected surfaces** The verifier, the focused test file, and the existing recall tests that prove runtime decisions.
- **Red** Compile fixtures with a mistyped grant, a grant bound to a different root, a forbidden literal `where` key, and an unknown literal `Access` binding or operation. Add positive controls for a valid grant, a valid named operation, a filter value from `input/1`, a dynamic grant or binding choice, and disabled recall. Check one diagnostic when two errors are visible. Keep the existing runtime test for denied dynamic filters.
- **Green and refactor** Use normalized plugin declarations and exact Flow identity. Check only literals the verifier can establish. Keep grant availability and filter enforcement in the existing runtime path. Return the binding or filter correction with the step name.
- **Gate and completion** Run the focused verifier and recall test files. Literal defects warn and dynamic input still goes through existing runtime checks.

#### U3 · Flag the direct context bypass and verify with examples

- **Outcome and requirements** R3, R4. A clear bypass warns. The direct recall and custom evidence examples compile and run quietly.
- **Dependencies** U2 provides step inspection and warning priority.
- **Affected surfaces** The verifier, the focused tests, and the [Answer from memory example README](../../examples/00_start_here/00_02_answer_from_memory/README.md).
- **Red** Compile a variant of the direct example with recall enabled unconditionally. Give `CallModel` the original context and use recall only in a trace. Expect one warning that names the model step. Add a variant with `needs` but no recall result in any model input. Keep positive cases for direct result references, an intermediate builder that reads recalled records, a conditionally enabled recall, and the two-call fit-and-check example. Check that the literal grant warning takes priority when both errors occur.
- **Green and refactor** Compare direct context references and use result dependencies to rule out recall input to the model. Limit the rule to the case in KTD3. Document the expected Agent DSL usage, the no-AI rule, and the manual-use option in the existing example README.
- **Gate and completion** Run the full suite and both fixture examples. The warning appears for the bad variant and both real examples complete without a memory wiring warning.

### Work Graph

Start with U1. U2 needs the compiler harness and step recognition from U1. U3 needs the warning selection and step inspection from U2. U1 → U2 → U3 is the critical path. U3 is the final integration gate.

### Verification Contract

| Requirements | Units | Evidence |
| --- | --- | --- |
| R1 | U1 | Compile and use a memory-only Agent. Check for zero memory wiring diagnostics. |
| R2 | U1 | Compile missing-step and correctly connected Agent fixtures. Check warning count, severity, and source. |
| R3 | U2, U3 | Compile literal-error and context-bypass fixtures. Check the valid, transformed, and dynamic cases in the same suite. |
| R4 | U1–U3 | Verify the option, one diagnostic per Agent, existing errors, and a quiet runtime. Run both examples. |

Run from the `jido_memory` Mix project root. For each slice, reproduce the specific assertion failure before adding the code. Match the relevant warning and source instead of the full compiler output. The examples use fixture inference when run without arguments.

```sh
mix test test/jido_memory/reasoning_verifier_test.exs
mix test test/jido_memory/reasoning_verifier_test.exs test/jido_memory/recall_for_model_test.exs test/jido_memory/agent_state_test.exs
mix format --check-formatted
mix test
mix example.memory
mix run examples/00_start_here/00_03_fit_and_check_evidence/run.exs
git diff --check
```

### Rollout and Recovery

The change takes effect when an Agent module compiles against the updated package. There is no data migration. An Agent author can turn off the advisory for intentional custom or non-reasoning memory use with `warn_unwired_reasoning false`.

### Risks and Assumptions

- Static visibility is limited to the published Flow definition. A custom Action or tool can use memory inside its implementation. The warning describes the visible root and points to the option for manual use.
- KTD1 uses a public Spark extension function and the Agent definition callback on the pinned baseline. Keep the real compile test as a compatibility check when Jido or Spark changes.
- The initial check treats static result references as evidence of a connection. It makes no claim that the model receives records on every request. Empty recall, denied access, and timeouts are runtime cases.

### Open Planning Decisions

No blocking decisions. The Jido Memory maintainer can propose nested Flow or custom Action coverage after reviewing the first implementation. That decision does not affect U1–U3.

### Definition of Done

All verification gates pass. The tests prove that non-AI memory is valid, AI wiring mistakes produce one compile-time warning, and corrected examples compile and run quietly. The example README shows the Agent-level option and when to use it.

### Planning Sources

- Pinned local dependencies. `deps/jido/lib/jido/agent/dsl.ex` and `agent/validation.ex` show the validation lifecycle. `deps/jido/lib/jido/ai/agent/plugin.ex` supplies the reasoning provider and root route. `deps/jido/lib/jido/flow.ex` and `flow/ref.ex` define the canonical Flow and its references. `deps/spark/lib/spark/dsl/extension.ex` and `dsl/verifier.ex` define verifier registration and results. [Lockfile](../../mix.lock)
- [Runtime grant and filter tests](../../test/jido_memory/recall_for_model_test.exs)
- [Memory-only Agent behavior tests](../../test/jido_memory/agent_state_test.exs)
- [Fixture example command](../../mix.exs)

## Adapter Results

- Markdown: canonical at `docs/plans/2026-11-22-1906-reasoning-memory-warnings-plan.md`
- HTML: not requested
- Beadwork: not requested
