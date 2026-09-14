# Codex research model policy

Honor explicit user model and effort choices. Otherwise dispatch research with
`gpt-5.6-terra` at `medium` effort, even when the parent uses another model.
This default applies to evidence gathering, documentation lookup, and feature
comparisons. It does not change implementation or review agents.

Use the available per-agent model and effort controls. With `spawn_agent`, set
`model: "gpt-5.6-terra"`, `reasoning_effort: "medium"`, and `fork_turns: "none"`.
A full-history fork inherits the parent settings and cannot apply this override.
Supply a self-contained brief with the question, relevant paths, constraints,
source requirements, and output location. When the client lacks these controls
or the model is unavailable, disclose the limitation and use its supported
default; never claim an override was applied.

Start with one research agent per bounded question. Reuse existing findings and
stop once the question is answered or the unresolved evidence gap is identified.
Return primary-source citations, applicable versions or dates, and uncertainties.
Distinguish documented facts from inference. The parent checks decision-critical
claims against their sources before using them to implement a change.

Use `gpt-5.6-sol` at `medium` effort for difficult synthesis or conflicting
evidence; use `gpt-6-astra` at `medium` or `high` for complex security guarantees
or architectural reasoning. State why the stronger model is needed. Escalate
only the unresolved question with the gathered evidence, preserving any explicit
user model constraint. Source unavailability alone is not a reason to escalate.
