# Jido Memory examples ladder

These examples build from a single model call to multi-Agent recall and
learning. Most use a support desk. The guide examples use Jido package
documentation. Each example shows a memory decision and its effect on the
Agent or operator.

## Start with the Agent

Open the Agent's `memory` block first. Send a Signal to its route and inspect
the reply. Use the Flow to follow the order of calls and the handling of
their results.

| Agent declaration | What it controls | First example |
| --- | --- | --- |
| `collection` | Record schema and retention limit in Agent state | [Remember a resolution](../examples/00_start_here/00_01_remember_a_resolution/README.md) |
| `external_collection` | Record schema and live store for recall | [Compare Agent state and ETS](../examples/03_store_locations/03_01_compare_agent_state_and_ets/README.md) |
| `read` | Filters, exposed fields, and result limit for a reasoning Flow | [Answer from memory](../examples/00_start_here/00_02_answer_from_memory/README.md) |
| `source` | Operations on a named source of evidence | [Read current account evidence](../examples/01_investigation/01_04_read_current_account/README.md) |
| `index` | Operations on a named search index | [Answer for an exact release](../examples/04_find_evidence/04_03_answer_for_an_exact_release/README.md) |
| `graph` | Operations on explicit relationships or graph retrieval | [Reopen a KG store](../examples/03_store_locations/03_04_reopen_a_kg_store/README.md) |

The same Agent can combine these declarations. The Ash articles Agent lists
and reads from an AshJido source, searches its Arcana index, and checks the
source again before sending an excerpt to the model. The guide library uses
a Git source and Arcana index. The GraphRAG example uses an index for hybrid
search and a graph binding for link traversal.

## 00 · Give the model evidence

1. **[Remember a resolution, then answer from it](../examples/00_start_here/00_02_answer_from_memory/README.md).**
   Seed the `T-17` resolution and send a question Signal through the Agent.
   Bind the Agent's read grant to its reasoning Flow. Run `ProjectConversation`,
   `RecallForModel`, and `CallModel` in order. Ask the same question with recall
   on and off. Trace the grant decision, source Signal ID, and exact model
   messages with the LLM fixture and LM Studio. Check that a different root
   Flow and an unapproved filter receive no evidence.
2. **[Fit evidence into the prompt and check the answer](../examples/00_start_here/00_03_fit_and_check_evidence/README.md).** Exceed the context
   budget and give the model a resolution that supports only part of its answer.
   In the Agent reasoning Flow, apply the budget before the first `CallModel`.
   Check the draft and give the revision call only the verified excerpt. Show
   the selected excerpts, the unsupported claim, and both prepared requests.

## 01 · Let the model investigate

3. **[Investigate an ambiguous charge](../examples/01_investigation/01_01_investigate_a_charge/README.md).** Let the model choose a memory tool and
   refine its query within two rounds. In a second case, ask one follow-up when
   the evidence stays ambiguous. Recall from the active Agent's declared
   collection in each round. Trace the filters, records, and stop condition.
4. **[Deny a lookup and continue the case](../examples/01_investigation/01_02_deny_a_lookup/README.md).** Give two customers the same ticket
   key. Show the model's request for the other customer's record, the scope
   enforced by the runtime, and the evidence it can use to continue.
5. **[Answer when a source times out](../examples/01_investigation/01_03_answer_after_timeout/README.md).** Search case history and the policy manual
   in parallel. After one retry, report what happened before and show why the
   Flow needs current policy evidence to recommend a refund.
6. **[Read current account evidence through AshJido](../examples/01_investigation/01_04_read_current_account/README.md).**
   The Agent's Flow calls the AshJido read Action for the application's
   `Account` resource. The host supplies the actor and tenant. Select the fields needed to explain refund
   eligibility and cite the source record. Run with two tenants that use the
   same account key. Check that only authorized fields from the current tenant
   reach the model and that a later read sees an account update.

## 02 · Review and commit model proposals

7. **[Learn from a closed ticket](../examples/02_review_and_commit/02_01_learn_from_a_closed_ticket/README.md).** Use a transcript and a successful refund
   Signal to propose a resolution and a customer preference. Use separate Flow
   steps to propose, review, and return a write Directive. Approve the resolution,
   hold the preference for confirmation, and recall on a later Turn.
8. **[Capture a confirmed outcome from an Ash resource](../examples/02_review_and_commit/02_02_capture_an_ash_outcome/README.md).** On a ticket-closed
   Signal, a Flow uses an AshJido read Action to load the committed refund
   outcome. Select the approved fields and save a typed resolution with its
   source key and revision. Replay the Signal and check that one memory record
   exists. Change the source before the next read and show which revision the
   Flow used. Check that a denied read creates no memory record.
9. **[Resolve an edit that arrives out of order](../examples/02_review_and_commit/02_03_resolve_out_of_order_edit/README.md).** Let a person correct a record
   with a pending model proposal. Redeliver the original Signal. Trace the
   stale proposal, duplicate capture, and source of the active value.
10. **[Recover a write after a lost acknowledgement](../examples/02_review_and_commit/02_04_recover_a_lost_acknowledgement/README.md).** Stop the Agent after Ecto
   applies a write. Restart and retry on SQLite and PostgreSQL. Follow one
   request ID to one stored record, a receipt, and a later answer.

## 03 · Change where memory lives

11. **[Compare checkpointed Agent state and shared ETS memory](../examples/03_store_locations/03_01_compare_agent_state_and_ets/README.md).** Run the same
   question across Agent restore, a second Agent, and an ETS table owner stop.
   Reuse the model-facing recall step across both stores. Show which records
   reach each model call.
12. **[Use an Ash resource as a memory store](../examples/03_store_locations/03_02_use_an_ash_memory_store/README.md).** Bind recall to an AshJido query Action.
    Apply value filters before the result limit. Use host-owned AshJido Actions
    for put, get, and delete. Use two actors and two tenants. Change access while
    a write is pending. Show the read and commit policy decisions for each actor.
13. **[Reject a stale result from an external adapter](../examples/03_store_locations/03_03_reject_a_stale_adapter_result/README.md).** Use the Mem0 package's
    Basic-over-ETS contract fixture as a model for a host-supplied test adapter.
    Run the same Flow with the built-in store and the fixture. Inject a result
    for an old revision. Trace the source check and show that the old result
    stays out of the model input.
14. **[Reopen a KG store without mixing scopes](../examples/03_store_locations/03_04_reopen_a_kg_store/README.md).** Adapt the KG demo to write a
    private preference and a shared project note to TripleStore. Reuse a record
    key in two scopes, reopen the store, and query as two Agents. Trace the RDF
    named graph for each hit and show that a denied scope supplies no evidence.

## 04 · Find the evidence that applies

15. **[Hand off an unfinished case with MemPalace](../examples/04_find_evidence/04_01_resume_with_mempalace/README.md).** Import a conversation and
    build wake-up context from its timeline, confirmed preference, and source
    links. A fresh Agent opens the passages that support the summary. Include
    an unconfirmed claim and show that the Agent asks before acting on it.
16. **[Reconstruct a decision as of two dates](../examples/04_find_evidence/04_02_reconstruct_a_decision/README.md).** Use MemPalace's dated facts to
    end the validity of an account fact and add its replacement. Include a
    retroactive correction and a new refund policy. Ask what applied on the
    refund date and what the Agent knew then. Cite the facts and versions used.
17. **[Fetch a guide and answer for an exact release](../examples/04_find_evidence/04_03_answer_for_an_exact_release/README.md).** An indexing
    Flow fetches each guide from Git, submits it to Arcana, and reports its status.
    On a later Turn, a fresh Agent searches the index for each version. Check that each
    answer cites its release and that a missing version reports a gap.
18. **[Rank evidence from several search paths](../examples/04_find_evidence/04_04_rank_evidence/README.md).** Use a paraphrase to compare
    lexical, vector, hybrid, and time-based retrieval. Use Arcana for document
    search. Trace the rankings, source checks, and evidence sent to the model.
19. **[Import a project and navigate its rooms](../examples/04_find_evidence/04_05_navigate_a_mempalace_project/README.md).** Use MemPalace to import a
    project with similar terms in authentication and billing. Let the Agent
    inspect wings, halls, and rooms, then narrow the search. Trace the room
    filter and the source file that supports the answer.
20. **[Follow a link across two guides with GraphRAG](../examples/04_find_evidence/04_06_follow_a_guide_link/README.md).** Ask a question that
    connects a product symptom to a repair procedure. Compare Arcana hybrid
    search and GraphRAG within the same release. Show which passages each mode
    finds and which ones support the answer.
21. **[Diagnose an issue across three graphs](../examples/04_find_evidence/04_07_diagnose_across_graphs/README.md).** Use KG for explicit relationships
    between the account, product, and experience graphs. Find a procedure
    tested for the product version. Trace supporting facts, ambiguous names,
    and the hop that access policy denied.

## 05 · Govern what the Agent learns

22. **[Turn case history into an approved procedure](../examples/05_govern_learning/05_01_approve_a_procedure/README.md).** Consolidate successful
    and failed cases into a candidate revision. Replay known cases, correct a
    regression, approve a version, and show a later model using it.
23. **[Trial a new capture rule in shadow mode](../examples/05_govern_learning/05_02_trial_a_capture_rule/README.md).** Run two rules on the same
    Signals. Show the records and fields each would capture and whether the
    extra memory improves an answer.
24. **[Forget a case while work is pending](../examples/05_govern_learning/05_03_forget_a_pending_case/README.md).** Delete a case with an Arcana
    index entry, a summary, and graph data. Release a delayed index write,
    restart the worker, and replay the Signal. Show why the record stays absent
    and what the model and trace viewers see.
25. **[Repair a failed Arcana index job](../examples/05_govern_learning/05_04_repair_an_index_job/README.md).** Use `IndexStatus` to find a failed
    guide and `IndexDocument` to retry it. Use `ReindexCollection` to resume
    an interrupted release import. Follow job IDs through failure and recovery.
    Check that each guide has one current document and can be cited again.
26. **[Index approved Ash knowledge articles](../examples/05_govern_learning/05_05_index_ash_articles/README.md).** Use a paginated AshJido read
    Action to load articles for one tenant. Index the approved fields in Arcana
    with a source key and revision. Reopen candidates through AshJido before
    supplying evidence. Withdraw an article or revoke access while index
    cleanup is pending. Check that stale excerpts stay out of the model input.

## 06 · Run the whole system

27. **[Resolve a case across Agents and sessions](../examples/06_run_the_system/06_01_resolve_across_agents/README.md).** Hand off a ticket, retrieve
    prior resolutions, check policy and procedure, answer with citations, and
    propose a record. Follow the approved change into the next case.
28. **[Find the cause of an answer regression](../examples/06_run_the_system/06_02_find_an_answer_regression/README.md).** Compare recall disabled, hybrid
    recall, and graphs with approved procedures. Measure task success, citation
    accuracy, latency, and tokens. Change one Flow, prompt, or model version
    and find where the traces first diverge.

29. **[Build the versioned Jido guide library](../examples/06_run_the_system/06_03_build_the_guide_library/README.md).** The Agent reads
    `guides/` from Git and indexes them in Arcana for each release in the catalog. Discover
    Hex releases and Git-only release tags. Resolve each release to a commit and
    keep the tag, commit, guide path, source URL, and checksum. Use one Arcana
    collection per package and version. Interrupt, resume, and repeat the import.
    Check for duplicate documents and report releases with no guides and releases
    that need repair. On a later Turn, compare two explicit versions and cite both.

## Build order for integration examples

Start with the exact-release Arcana example, the KG reopen example, and the
MemPalace wake-up example. Use pinned fixtures to assert model input and answers.
Add opt-in runs against the actual backends to verify their behavior. Reuse the
small Arcana example's Actions in the full-catalog Flow.

Start the AshJido source examples with a real generated read Action on a
disposable Ash resource. Reuse the actor and tenant fixture for live evidence,
capture, and indexed articles. Use the compatible AshJido version from the
[v3 compatibility plan](https://github.com/agentjido/jido_memory/blob/release/v3/docs/plans/2026-11-22-1614-jido-v3-memory-plan.md#u4--prepare-and-verify-the-ashjido-version-fixture).

## Read the traces

Each script prints its trace and answer to standard output. The model calls
record the prepared messages in `model_input`. Tool examples also record
the tool definitions, arguments, and results. Read the other trace fields
to follow access decisions, source revisions, and the IDs of Signals, records,
receipts, and jobs. The script checks the expected fields before it exits.

In **Answer from memory**, the runner prints the Agent reply's `memory_trace`
as `trace`. Compare `trace.recall`, `trace.model_input`, and
`trace.request_digest` for the two runs. The recall trace links evidence to
its source Signal. The enabled request includes the approved resolution.
The disabled request omits it.
Each linked example includes a fixture command and a ReqLLM mode.

## Verified runs

| Examples | Verification |
| --- | --- |
| 1–5 | Fixture and LM Studio `lfm3-1.7b`. Checked recall on and off, evidence limits, tool arguments, scope denial, and the policy timeout. |
| 6–9 | AshJido `e4374e8` where applicable. Fixture and LM Studio for the model calls. Checked tenant scope, policy denial, source revision, proposed writes, and replay. |
| 10 | SQLite and PostgreSQL 18.6. Checked one record and one receipt after reactivation. Verified the later model call with the fixture and LM Studio. |
| 11 | Actual ETS table and Jido checkpoint restore. Fixture and LM Studio. Checked Agent isolation, shared scope, and owner-stop behavior. |
| 12 | AshJido `e4374e8` against the Ash ETS data layer. Fixture and LM Studio. Checked tenant mismatch, write revocation, and then read revocation. |
| 13 | Agent state and a host adapter backed by ETS. Fixture and LM Studio. Revision 2 supplied evidence. The Flow excluded the text of revision 1 before inference. |
| 14 | TripleStore with RocksDB. Fixture and LM Studio. Both named graphs kept their own value after reopen. Bob's denied read supplied no evidence. |
| 15 | MemPalace `f009d83` with SQLite. Fixture and LM Studio. Opened two drawers and withheld the pending change. The live response was empty, so the Flow issued the required confirmation question. |
| 16 | MemPalace `f009d83` with SQLite. Fixture and LM Studio. Both model runs reproduced the cited account revision and policy for all three date pairs. |
| 17 | Arcana 4.0.3, PostgreSQL 18.6, and pgvector. Fixture and LM Studio. Two Git tags produced separate citations and the unindexed version produced a gap. The Flow used the verified result for live replies that paraphrased it. |
| 18 | Arcana and pgvector. Fixture and LM Studio. Checked four rankings. Only the current 30-day policy passed source review. |
| 19 | MemPalace and SQLite. Fixture and LM Studio. The billing filter excluded the authentication room, and both model replies cited the billing file. |
| 20 | Arcana GraphRAG and pgvector. Fixture and LM Studio. Hybrid and direct mentions found the symptom. One graph hop reached the repair. The Flow kept the full citations when LM Studio used numbered references. |
| 21 | TripleStore with RocksDB. Fixture and LM Studio. The account device ID resolved the name conflict. The Flow excluded the old repair and made zero reads on the denied hop. |
| 22 | Jido Agent memory. The fixture proposed the draft. LM Studio returned an empty proposal, so replay used the example baseline. Both runs exposed only the approved revision to the later model call. |
| 23 | Jido Agent memory. Fixture and LM Studio. Both gave the correct refund reason with shadow evidence. The active record kept only the resolution. |
| 24 | Arcana, PostgreSQL and Jido Agent memory. Fixture and LM Studio. The document, chunk, graph entity, and summary were absent after deletion, delayed write, and replay. |
| 25 | Arcana and PostgreSQL. Fixture and LM Studio. The job kept its ID through failure and retry. The resumed import and repeat kept one document per guide. |
| 26 | AshJido, Arcana, and PostgreSQL. Fixture and LM Studio. The filtered import returned two pages. The withdrawn and revoked runs found the old index hit and kept it out of the model input. |
| 27 | Two live Jido Agent servers and two AI sessions. Fixture and LM Studio. The first model received `T-17`. The next received `T-18` and the approved receipt `R-18`. |
| 28 | Arcana GraphRAG and Jido Agent memory. Fixture and LM Studio. The repair succeeded only with depth one and the approved procedure. The trace located the change at `retrieve`. Live inputs used 56, 76, 112, and 76 tokens for disabled, hybrid, graph, and regression. |
| 29 | Arcana and PostgreSQL. Fixture and LM Studio. The public catalog run imported 4,360 guides from 228 releases across a catalog of 79 packages. The repeat skipped all 4,360 jobs and found zero duplicate documents. Discovery flagged 103 releases without guides, 13 Hex releases without a matching source tag, and 13 packages without a release. The final live answer cited the Agent guide from each release. |
