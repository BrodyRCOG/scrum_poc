#!/usr/bin/env bash
#
# create_requirements.sh
#
# Reads a JSON array of structured requirements (see requirements.example.json
# for the expected shape) and, for each one:
#   1. Creates a GitHub issue in the target repo (body formatted like the
#      "Requirement" issue form, so manually-created and agent-created issues
#      look the same).
#   2. Adds that issue to the GitHub Project (Table view).
#   3. Sets every custom Project field (Priority, Req Type, NFR Category,
#      Epic, Story Points, Source, Clarification Status, Confidence) on the
#      new Project item.
#
# Status and Sprint are intentionally left alone here — those are typically
# set by the team's workflow (Status defaults to "Backlog" automatically in
# most Project configs, and Sprint/iteration assignment is a planning step).
#
# Requirements:
#   - GitHub CLI (`gh`), authenticated: gh auth login
#   - `jq`
#   - gh project extension is built in to modern gh, no extra install needed
#
# Usage:
#   ./create_requirements.sh <requirements.json> <owner/repo> <project-owner> <project-number>
#
# Example:
#   ./create_requirements.sh requirements.json BrodyRCOG/my-repo BrodyRCOG 1

set -euo pipefail

REQS_FILE="${1:?Usage: $0 <requirements.json> <owner/repo> <project-owner> <project-number>}"
REPO="${2:?Missing owner/repo, e.g. BrodyRCOG/my-repo}"
PROJECT_OWNER="${3:?Missing project owner, e.g. BrodyRCOG}"
PROJECT_NUMBER="${4:?Missing project number, e.g. 1}"

command -v gh  >/dev/null || { echo "gh CLI not found. Install: https://cli.github.com" >&2; exit 1; }
command -v jq  >/dev/null || { echo "jq not found. Install jq first." >&2; exit 1; }

if [[ ! -f "$REQS_FILE" ]]; then
  echo "Requirements file not found: $REQS_FILE" >&2
  exit 1
fi

echo "==> Looking up project metadata for $PROJECT_OWNER (project #$PROJECT_NUMBER)..."

PROJECT_JSON="$(gh project view "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json)"
PROJECT_ID="$(echo "$PROJECT_JSON" | jq -r '.id')"

FIELDS_JSON="$(gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json)"

# Helper: get a field's id by its exact name
field_id() {
  echo "$FIELDS_JSON" | jq -r --arg name "$1" '.fields[] | select(.name == $name) | .id'
}

# Helper: get a single-select option's id by field name + option name
option_id() {
  local field_name="$1" option_name="$2"
  echo "$FIELDS_JSON" | jq -r --arg f "$field_name" --arg o "$option_name" \
    '.fields[] | select(.name == $f) | .options[] | select(.name == $o) | .id'
}

FIELD_ID_PRIORITY="$(field_id "Priority")"
FIELD_ID_REQTYPE="$(field_id "Req Type")"
FIELD_ID_NFR="$(field_id "NFR Category")"
FIELD_ID_EPIC="$(field_id "Epic")"
FIELD_ID_POINTS="$(field_id "Story Points")"
FIELD_ID_SOURCE="$(field_id "Source")"
FIELD_ID_CLARIFY="$(field_id "Clarification Status")"
FIELD_ID_CONFIDENCE="$(field_id "Confidence")"

for pair in "Priority:$FIELD_ID_PRIORITY" "Req Type:$FIELD_ID_REQTYPE" "NFR Category:$FIELD_ID_NFR" \
            "Epic:$FIELD_ID_EPIC" "Story Points:$FIELD_ID_POINTS" "Source:$FIELD_ID_SOURCE" \
            "Clarification Status:$FIELD_ID_CLARIFY" "Confidence:$FIELD_ID_CONFIDENCE"; do
  name="${pair%%:*}"; id="${pair##*:}"
  if [[ -z "$id" || "$id" == "null" ]]; then
    echo "WARNING: could not find a Project field named '$name'. Check spelling/case in the Project settings." >&2
  fi
done

COUNT="$(jq 'length' "$REQS_FILE")"
echo "==> Found $COUNT requirement(s) in $REQS_FILE"

for i in $(seq 0 $((COUNT - 1))); do
  ITEM="$(jq -c ".[$i]" "$REQS_FILE")"

  TITLE="$(echo "$ITEM" | jq -r '.title')"
  DESCRIPTION="$(echo "$ITEM" | jq -r '.description // ""')"
  AC="$(echo "$ITEM" | jq -r '(.acceptance_criteria // []) | map("- [ ] " + .) | join("\n")')"
  REQ_TYPE="$(echo "$ITEM" | jq -r '.req_type // ""')"
  NFR_CATEGORY="$(echo "$ITEM" | jq -r '.nfr_category // "N/A"')"
  PRIORITY="$(echo "$ITEM" | jq -r '.priority // ""')"
  EPIC="$(echo "$ITEM" | jq -r '.epic // ""')"
  STORY_POINTS="$(echo "$ITEM" | jq -r '.story_points // empty')"
  SOURCE="$(echo "$ITEM" | jq -r '.source // ""')"
  CLARIFICATION="$(echo "$ITEM" | jq -r '.clarification_status // ""')"
  CONFIDENCE="$(echo "$ITEM" | jq -r '.confidence // ""')"

  echo ""
  echo "==> [$((i + 1))/$COUNT] Creating issue: $TITLE"

  BODY=$(cat <<EOF
### Description

$DESCRIPTION

### Acceptance Criteria

$AC

### Requirement Type
$REQ_TYPE

### NFR Category
$NFR_CATEGORY

### Priority
$PRIORITY

### Epic
$EPIC

### Story Points
${STORY_POINTS:-N/A}

### Source
$SOURCE

### Clarification Status
$CLARIFICATION

### Confidence
$CONFIDENCE
EOF
)

  ISSUE_URL="$(gh issue create --repo "$REPO" --title "$TITLE" --body "$BODY" --label "requirement")"
  echo "    Created: $ISSUE_URL"

  ITEM_ID="$(gh project item-add "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --url "$ISSUE_URL" --format json | jq -r '.id')"
  echo "    Added to project as item: $ITEM_ID"

  set_select() {
    local field_id="$1" field_name="$2" value="$3"
    [[ -z "$value" || "$value" == "null" ]] && return 0
    local opt_id
    opt_id="$(option_id "$field_name" "$value")"
    if [[ -z "$opt_id" ]]; then
      echo "    WARNING: option '$value' not found for field '$field_name' — skipping." >&2
      return 0
    fi
    gh project item-edit --id "$ITEM_ID" --project-id "$PROJECT_ID" \
      --field-id "$field_id" --single-select-option-id "$opt_id" >/dev/null
  }

  set_text() {
    local field_id="$1" value="$2"
    [[ -z "$value" || "$value" == "null" ]] && return 0
    gh project item-edit --id "$ITEM_ID" --project-id "$PROJECT_ID" \
      --field-id "$field_id" --text "$value" >/dev/null
  }

  set_number() {
    local field_id="$1" value="$2"
    [[ -z "$value" || "$value" == "null" ]] && return 0
    gh project item-edit --id "$ITEM_ID" --project-id "$PROJECT_ID" \
      --field-id "$field_id" --number "$value" >/dev/null
  }

  set_select "$FIELD_ID_PRIORITY"    "Priority"             "$PRIORITY"
  set_select "$FIELD_ID_REQTYPE"     "Req Type"             "$REQ_TYPE"
  set_select "$FIELD_ID_NFR"         "NFR Category"         "$NFR_CATEGORY"
  set_text   "$FIELD_ID_EPIC"        "$EPIC"
  set_number "$FIELD_ID_POINTS"      "$STORY_POINTS"
  set_text   "$FIELD_ID_SOURCE"      "$SOURCE"
  set_select "$FIELD_ID_CLARIFY"     "Clarification Status" "$CLARIFICATION"
  set_select "$FIELD_ID_CONFIDENCE"  "Confidence"           "$CONFIDENCE"

  echo "    Fields set."
done

echo ""
echo "==> Done. $COUNT requirement(s) created and added to the project."
