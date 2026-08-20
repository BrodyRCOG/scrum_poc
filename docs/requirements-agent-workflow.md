# Requirements Intake Agent — Workflow

This describes how a Claude agent (Claude Code is the natural fit, since it can
run shell commands directly) turns an unstructured client requirements dump
(a plain list, or a full client email) into GitHub issues that show up fully
populated in the Project Table view.

## Overview

```
client email / list  --->  Claude parses & structures  --->  requirements.json
                                                                      |
                                                                      v
                                          scripts/create_requirements.sh
                                                                      |
                                                                      v
                                     GitHub issues + Project items, all
                                     fields set (Priority, Req Type, etc.)
```

Two steps, always in this order:

1. **Extraction step (Claude does the reading).** Claude reads whatever the
   client sent — a numbered list, prose in an email, a mix of both — and
   converts it into a JSON array matching the schema below. This is a
   judgment call, not a mechanical parse, so this is the part that actually
   needs the model rather than a regex script.
2. **Creation step (the script does the writing).** `create_requirements.sh`
   takes that JSON and does the mechanical GitHub CLI work: create issue, add
   to project, set fields.

Keeping these separate means the script never has to trust free text, and
Claude never has to remember `gh` flag syntax.

## Step 1: Extraction prompt

Give Claude (in Claude Code, or via the API) a prompt along these lines,
with the client's raw text pasted in or attached:

> You are extracting software requirements from raw client input for a
> GitHub Project. Read the text below and produce a JSON array where each
> element is one discrete requirement, following exactly this schema:
>
> ```json
> {
>   "title": "short imperative summary, <= 70 chars",
>   "description": "1-3 sentences restating the requirement clearly",
>   "acceptance_criteria": ["specific, testable condition", "..."],
>   "req_type": "Functional | Non-Functional | Unclear",
>   "nfr_category": "Performance | Security | Usability | Reliability | Scalability | Compliance | Maintainability | N/A",
>   "priority": "P0 | P1 | P2",
>   "epic": "short grouping label, e.g. 'Account Management'",
>   "story_points": null,
>   "source": "one line describing where this came from, e.g. 'Client email, 2026-08-18, subject: MVP scope'",
>   "clarification_status": "Needs Client Input | Needs Clarification | Confirmed",
>   "confidence": "Firm | Assumed | Guess"
> }
> ```
>
> Rules:
> - If the client's wording is vague, set `req_type` to `Unclear` and
>   `clarification_status` to `Needs Clarification` or `Needs Client Input`
>   rather than guessing at intent.
> - Set `confidence` honestly: `Firm` only if the requirement is stated
>   explicitly and unambiguously; `Assumed` if you inferred it from context;
>   `Guess` if you're filling a gap the client left open.
> - Leave `story_points` as `null` — estimation happens later, by the team.
> - Split compound requirements ("the system should X and also Y") into
>   separate items if X and Y are independently testable/assignable.
> - Do not invent requirements that aren't implied by the source text.
> - Output ONLY the JSON array, no prose, no markdown fences.

This is the part worth iterating on with a few real client emails — tune the
rules until the splitting/priority/confidence judgment calls match how your
team actually wants things triaged.

## Step 2: Run the creation script

```bash
chmod +x scripts/create_requirements.sh
./scripts/create_requirements.sh requirements.json BrodyRCOG/<your-repo> BrodyRCOG 1
```

- `requirements.json` — the output of Step 1.
- `BrodyRCOG/<your-repo>` — the repo issues get created in.
- `BrodyRCOG` / `1` — the Project owner and number (from
  `https://github.com/users/BrodyRCOG/projects/1`).

The script looks up field and option IDs from the live Project at run time
(via `gh project field-list`), so it keeps working even if you rename an
option or add new ones later — nothing is hardcoded except the field *names*
(`Priority`, `Req Type`, etc.), which must match exactly what's in your
Project settings.

**Status** and **Sprint** are left untouched by the script on purpose:
Status should default to your Project's default column (Backlog), and Sprint
assignment is a planning decision your team makes deliberately, not something
that should be auto-guessed from a client email.

## Wiring it up as a Claude Code workflow

If you want this to feel like one command instead of two:

1. Save the extraction prompt (Step 1) as a Claude Code slash command or a
   short skill, e.g. `/intake-requirements`, that takes pasted text or an
   attached email, and writes `requirements.json` to the repo.
2. Have that same command finish by running
   `./scripts/create_requirements.sh requirements.json <repo> <owner> <project-number>`.
3. Now the flow is: paste the client email → run `/intake-requirements` →
   issues appear in the Project Table view, fully tagged.

## Sanity-check before running against a real client email

Because this creates real issues, it's worth having Claude print the
extracted JSON and asking for a quick human glance before Step 2 runs,
especially on the first few runs — mainly to catch over-splitting or
mis-triaged priority, not because the mechanics are unreliable.

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth login`) with access to both
  the repo and the Project (Projects require the `project` scope — run
  `gh auth refresh -s project` if you hit permission errors).
- `jq` installed.
- Field **names** in the script must exactly match your Project's field
  names (case-sensitive): `Priority`, `Req Type`, `NFR Category`, `Epic`,
  `Story Points`, `Source`, `Clarification Status`, `Confidence`.
