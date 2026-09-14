@AGENTS.md

# Claude Code

The imported `AGENTS.md` guide is mandatory and is the canonical cross-agent
contributor policy. For non-trivial work, act as the orchestrator: create the
capability map, assign independent scopes through the available worker
mechanism, integrate their work, and commission the required fresh specialist
review. Provider-native subagents are optional and must not be assumed to be
the portable correctness path. Do not merely relay worker reports as the final
answer.

Inspect the working tree before editing because local feature work may be
uncommitted. Do not run `/init` to replace this file, and do not start
interactive Codex, Claude, Cursor, or other provider authentication as part of
repository checks.
