# Examples

This folder holds runnable example scripts for `jido_memory`.

## Jido v3

Run `mix example.memory` from the package root to start with the model fixture.
Start with the Agent's `memory` block in each example. Its Signal routes
identify the operations that the runner exercises. Follow the routed Actions
and Flows to see how the Agent collects, checks, and uses the evidence.

The [exact-release Agent](04_find_evidence/04_03_answer_for_an_exact_release/run.exs)
binds a Git source and an Arcana index. The
[KG Agent](03_store_locations/03_04_reopen_a_kg_store/run.exs) binds a graph.
The [Ash articles Agent](05_govern_learning/05_05_index_ash_articles/run.exs)
uses both a source and an index. See the
[memory DSL guide](../docs/plans/jido-v3-memory-dsl.md#bind-a-source-index-or-graph)
for the binding syntax.

- [Answer from memory](00_start_here/00_02_answer_from_memory/README.md) runs the
  same model request with recall enabled and disabled. Use the offline fixture
  or a live ReqLLM configuration.
- [Remember a resolution](00_start_here/00_01_remember_a_resolution/README.md)
  shows how the Agent stores the ticket that seeds the model example.
- [Fit and check evidence](00_start_here/00_03_fit_and_check_evidence/README.md)
  bounds the excerpts and checks a cited draft before revision.
- [Examples ladder](../docs/examples-ladder.md) lists all 29 examples and their verification.

### Investigation

- [Investigate an ambiguous charge](01_investigation/01_01_investigate_a_charge/README.md)
  lets the model refine a lookup in two tool rounds.
- [Deny a lookup and continue](01_investigation/01_02_deny_a_lookup/README.md)
  checks the requested customer against the active Agent.
- [Answer after a source timeout](01_investigation/01_03_answer_after_timeout/README.md)
  reports a prior resolution and defers a recommendation when policy is unavailable.
- [Read current account evidence through AshJido](01_investigation/01_04_read_current_account/README.md)
  checks actor policy, tenant scope, and a later source revision before the model answers.

### Review and commit

- [Learn from a closed ticket](02_review_and_commit/02_01_learn_from_a_closed_ticket/README.md)
  reviews the model's proposals and recalls the approved resolution on a later Turn.
- [Capture a confirmed Ash outcome](02_review_and_commit/02_02_capture_an_ash_outcome/README.md)
  saves a source revision and checks replay and denied reads.
- [Resolve an edit that arrives out of order](02_review_and_commit/02_03_resolve_out_of_order_edit/README.md)
  rejects a stale model proposal and cites the human correction on a later Turn.
- [Recover a write after a lost acknowledgement](02_review_and_commit/02_04_recover_a_lost_acknowledgement/README.md)
  restores a pending request and reuses its receipt on SQLite and PostgreSQL.

### Change where memory lives

- [Compare checkpointed Agent state and shared ETS memory](03_store_locations/03_01_compare_agent_state_and_ets/README.md)
  runs the same model-facing recall step against both stores.
- [Use an Ash resource as a memory store](03_store_locations/03_02_use_an_ash_memory_store/README.md)
  checks tenant scope and permission changes before recall and commit.
- [Reject a stale result from an external adapter](03_store_locations/03_03_reject_a_stale_adapter_result/README.md)
  checks the candidate's source revision before it enters the model prompt.
- [Reopen a KG store without mixing scopes](03_store_locations/03_04_reopen_a_kg_store/README.md)
  checks private and shared RDF named graphs after closing and reopening TripleStore.

### Find the evidence that applies

- [Hand off an unfinished case with MemPalace](04_find_evidence/04_01_resume_with_mempalace/README.md)
  opens conversation passages and holds an unconfirmed change.
- [Reconstruct a decision as of two dates](04_find_evidence/04_02_reconstruct_a_decision/README.md)
  cites the account fact and policy that applied and were known at each date.
- [Fetch a guide and answer for an exact release](04_find_evidence/04_03_answer_for_an_exact_release/README.md)
  indexes two Git tags in Arcana and checks that each answer cites the requested release.
- [Rank evidence from several search paths](04_find_evidence/04_04_rank_evidence/README.md)
  checks keyword, vector, hybrid, and date rankings before the model sees evidence.
- [Import a project and navigate its rooms](04_find_evidence/04_05_navigate_a_mempalace_project/README.md)
  uses MemPalace room metadata to find the billing callback instructions.
- [Follow a link across two guides with GraphRAG](04_find_evidence/04_06_follow_a_guide_link/README.md)
  follows a stored relationship to find the repair that hybrid search missed.
- [Diagnose an issue across three graphs](04_find_evidence/04_07_diagnose_across_graphs/README.md)
  checks the product identity, the tested version, and access at each graph.

### Govern what the Agent learns

- [Turn case history into an approved procedure](05_govern_learning/05_01_approve_a_procedure/README.md)
  checks a draft against held-out cases before an operator approves a revision.
- [Trial a new capture rule in shadow mode](05_govern_learning/05_02_trial_a_capture_rule/README.md)
  compares two model inputs and keeps the shadow fields out of stored memory.
- [Forget a case while work is pending](05_govern_learning/05_03_forget_a_pending_case/README.md)
  checks that deletion survives a delayed write and worker restart.
- [Repair a failed Arcana index job](05_govern_learning/05_04_repair_an_index_job/README.md)
  retries one failed guide and resumes the import without duplicate documents.
- [Index approved Ash knowledge articles](05_govern_learning/05_05_index_ash_articles/README.md)
  checks current Ash policy and publication status before it supplies an indexed article to the model.

### Run the whole system

- [Resolve a case across Agents and sessions](06_run_the_system/06_01_resolve_across_agents/README.md)
  follows a handoff and approved resolution into a new AI session.
- [Find the cause of an answer regression](06_run_the_system/06_02_find_an_answer_regression/README.md)
  compares exact model inputs and finds the graph step that lost the repair.
- [Build the versioned Jido guide library](06_run_the_system/06_03_build_the_guide_library/README.md)
  resumes a catalog import and cites two explicit releases in a later answer.
