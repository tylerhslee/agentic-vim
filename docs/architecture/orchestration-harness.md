# Orchestration harness architecture

Status: foundational design; the workflow described here is not implemented
yet.

Agentic Vim will provide a provider-neutral orchestration harness on top of
ordinary Agent Client Protocol (ACP) sessions. Neovim, rather than an individual
provider, owns the workflow. Provider-native subagents may be exposed later as
an opt-in optimization, but they are not part of the correctness path.

## Product boundaries

The product has three layers with deliberately different responsibilities:

1. **Agentic Vim distribution.** Installs and configures the isolated Neovim
   product, providers, UI, and pinned dependencies.
2. **Agentic.nvim-derived session bridge.** Supplies generic ACP session
   primitives: create a session with an explicit working directory, submit a
   prompt, cancel or destroy a session, and subscribe to normalized events. It
   contains no planner, worker, or product-policy concepts.
3. **Agentic harness extension.** Owns plans, role prompts, validation,
   scheduling, workspace isolation, patch collection, integration, review,
   verification, persistence, and workflow UI.

The harness will use the `agentic_harness` Lua namespace. Its only dependency
on Agentic.nvim internals must pass through one adapter so that the workflow
model can be tested without a live provider and the bridge can evolve without
spreading coupling throughout the extension.

## Portable capability gate

Provider-neutral means the harness relies on a portable contract, not that
every ACP implementation is automatically safe to run. Before dispatch, the
Agentic.nvim bridge must demonstrate independent ordinary sessions, explicit
session working directories, prompt submission, normalized completion and
error events, and cancellation. The harness must also be able to enforce its
workspace boundary outside the prompt. Missing capabilities block harness
execution; they never trigger a fallback to provider-native subagents or an
unsafe prompt-only policy. A provider that serializes otherwise independent
sessions may reduce throughput without changing correctness.

## Capability plan

The planner optimizes for separability, not elapsed time. It decomposes the
requested result into mutually exclusive and collectively exhaustive (MECE)
capabilities. Dependencies only determine which validated capabilities can run
in the same wave.

Each capability record must define:

- a unique ID and cohesive objective;
- explicit inclusions and exclusions;
- input, output, and invariant contracts at its interfaces;
- dependencies on other capability contracts;
- exclusive repository-relative write paths and read-only dependencies;
- the required specialty and deliverable;
- objective acceptance criteria and verification commands; and
- shared or cross-cutting seams reserved for integration.

Before dispatch, validation rejects duplicate or missing IDs, dependency cycles,
overlapping write paths (including ancestor and descendant paths), writes to an
integration-only path, ambiguous ownership, and incomplete contracts. Mechanical
validation cannot prove collective exhaustiveness, so the planner must include a
coverage claim and a separate plan-review gate must challenge omissions and
duplication.

Files such as shared registries, public indexes, lockfiles, release metadata,
and cross-cutting documentation normally remain integration-owned. If two
capabilities cannot be implemented without editing the same owned path, they
are one worker scope unless the interface can be frozen first.

## Workflow and write isolation

The Neovim-controlled state machine is:

```text
draft -> validating -> ready -> dispatching -> collecting
      -> integrating -> reviewing -> verifying -> completed
```

Failed, cancelled, and paused are explicit persisted outcomes. A scheduler
derives runnable waves from validated dependencies and exclusive ownership;
there is no timeline field in the plan.

Before dispatch, the harness creates one immutable baseline snapshot representing
the canonical working tree, including relevant dirty tracked and untracked
state. Every worker session uses an isolated view of that snapshot as its
working directory and has no write access to the canonical tree. If the runtime
cannot enforce that boundary, the harness refuses to dispatch workers.

The initial execution path is correctness-first:

- workers read the immutable snapshot and return structured findings or patch
  proposals through ACP or harness-owned artifact storage;
- the harness records canonical state before fan-out and detects independent
  user drift before integration;
- drift pauses integration and is never repaired with an automatic stash,
  reset, checkout, or rollback; and
- one integration session alone receives canonical write access, followed by
  fresh isolated review and repository-wide verification.

Prompt instructions and post-hoc drift detection are not isolation boundaries;
drift detection is defense in depth for changes made independently of workers.
A later stage may give writing workers private writable copies of the frozen
snapshot and reconcile their patches against its identity. File modes, symlinks,
submodules, ignored-file policy, and canonical drift are part of the snapshot
contract.

## Versioned model

Persisted workflow records begin with `schema_version = 1` and include the
repository root, original request, provider selection, baseline identity,
phase, capability records, worker runs, returned artifacts, review findings,
and verification results. Persistence must be atomic and must avoid recording
credentials or unnecessary source contents.

The public extension facade is expected to remain small: `setup`, `start`,
`cancel`, `resume`, and `status`. Planner output is untrusted input and must be
parsed into the versioned model and validated before it can cause session or
filesystem actions.

## Delivery stages

1. Define this contract and the maintained-fork boundary.
2. Add the pure plan validator and workflow transition model with provider-free
   tests.
3. Expose and test the narrow ACP session bridge, including explicit session
   working directories.
4. Implement immutable snapshot workspaces, enforced canonical isolation,
   read-only workers, structured artifact collection, canonical-drift detection,
   and single-writer integration.
5. Add private writable worker workspaces and patch reconciliation.
6. Add persistence, dashboard controls, adversarial review, and verification
   gates.
7. Optionally support provider-native subagents behind an explicit capability
   and user setting.

Existing Agentic chat and provider-originated subagent telemetry remain separate
from this workflow until the corresponding stage is implemented.
