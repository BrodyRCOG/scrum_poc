#!/bin/bash

# Script to update GitHub Projects V2 custom fields for requirement issues
# Usage: ./scripts/update_project_fields.sh
# Prerequisites: gh CLI installed and authenticated with project scope

PROJECT_OWNER="BrodyRCOG"
PROJECT_NUMBER="1"
REPO="BrodyRCOG/scrum_poc"

# First, fetch the project to get field IDs
echo "Fetching project details and field IDs..."

PROJECT_QUERY=$(cat <<'EOF'
query {
  user(login: "BrodyRCOG") {
    projectV2(number: 1) {
      id
      fields(first: 20) {
        nodes {
          ... on ProjectV2Field {
            id
            name
          }
          ... on ProjectV2IterationField {
            id
            name
          }
          ... on ProjectV2SingleSelectField {
            id
            name
            options {
              id
              name
            }
          }
        }
      }
    }
  }
}
EOF
)

PROJECT_DATA=$(gh api graphql -f query="$PROJECT_QUERY")
echo "Project data retrieved:"
echo "$PROJECT_DATA" | jq '.'

# Extract project ID and field IDs
PROJECT_ID=$(echo "$PROJECT_DATA" | jq -r '.data.user.projectV2.id')
echo "Project ID: $PROJECT_ID"

# Helper function to get field ID by name
get_field_id() {
  local field_name="$1"
  echo "$PROJECT_DATA" | jq -r ".data.user.projectV2.fields.nodes[] | select(.name == \"$field_name\") | .id"
}

# Helper function to get option ID by field name and option name
get_option_id() {
  local field_name="$1"
  local option_name="$2"
  echo "$PROJECT_DATA" | jq -r ".data.user.projectV2.fields.nodes[] | select(.name == \"$field_name\") | .options[] | select(.name == \"$option_name\") | .id"
}

# Get all field IDs
PRIORITY_FIELD_ID=$(get_field_id "Priority")
REQ_TYPE_FIELD_ID=$(get_field_id "Req Type")
NFR_CATEGORY_FIELD_ID=$(get_field_id "NFR Category")
EPIC_FIELD_ID=$(get_field_id "Epic")
STORY_POINTS_FIELD_ID=$(get_field_id "Story Points")
SOURCE_FIELD_ID=$(get_field_id "Source")
CLARIFICATION_STATUS_FIELD_ID=$(get_field_id "Clarification Status")
CONFIDENCE_FIELD_ID=$(get_field_id "Confidence")

echo ""
echo "Field IDs:"
echo "Priority: $PRIORITY_FIELD_ID"
echo "Req Type: $REQ_TYPE_FIELD_ID"
echo "NFR Category: $NFR_CATEGORY_FIELD_ID"
echo "Epic: $EPIC_FIELD_ID"
echo "Story Points: $STORY_POINTS_FIELD_ID"
echo "Source: $SOURCE_FIELD_ID"
echo "Clarification Status: $CLARIFICATION_STATUS_FIELD_ID"
echo "Confidence: $CONFIDENCE_FIELD_ID"
echo ""

# Function to add issue to project and set fields
add_and_update_issue() {
  local issue_number="$1"
  local priority="$2"
  local req_type="$3"
  local nfr_category="$4"
  local epic="$5"
  local story_points="$6"
  local source="$7"
  local clarification_status="$8"
  local confidence="$9"

  echo "Processing issue #$issue_number..."

  # Get issue URL
  ISSUE_URL="https://github.com/$REPO/issues/$issue_number"

  # Query to get or add item to project
  ADD_ITEM_QUERY=$(cat <<EOF
mutation {
  addProjectV2ItemById(input: {projectId: "$PROJECT_ID", contentId: "$(gh api repos/$REPO/issues/$issue_number --jq '.node_id' 2>/dev/null || echo '')"}) {
    item {
      id
    }
  }
}
EOF
)

  # First, get the issue node_id
  ISSUE_NODE_ID=$(gh api repos/$REPO/issues/$issue_number --jq '.node_id')
  echo "  Issue node_id: $ISSUE_NODE_ID"

  # Add item to project
  ADD_ITEM_QUERY=$(cat <<EOF
mutation {
  addProjectV2ItemById(input: {projectId: "$PROJECT_ID", contentId: "$ISSUE_NODE_ID"}) {
    item {
      id
    }
  }
}
EOF
)

  ITEM_RESPONSE=$(gh api graphql -f query="$ADD_ITEM_QUERY")
  ITEM_ID=$(echo "$ITEM_RESPONSE" | jq -r '.data.addProjectV2ItemById.item.id')
  echo "  Item ID: $ITEM_ID"

  if [ "$ITEM_ID" == "null" ] || [ -z "$ITEM_ID" ]; then
    echo "  Error: Could not add item to project"
    return 1
  fi

  # Update fields
  # Priority
  if [ -n "$PRIORITY_FIELD_ID" ] && [ "$PRIORITY_FIELD_ID" != "null" ]; then
    PRIORITY_OPTION_ID=$(get_option_id "Priority" "$priority")
    if [ -n "$PRIORITY_OPTION_ID" ] && [ "$PRIORITY_OPTION_ID" != "null" ]; then
      UPDATE_QUERY=$(cat <<EOF
mutation {
  updateProjectV2ItemFieldValue(input: {projectId: "$PROJECT_ID", itemId: "$ITEM_ID", fieldId: "$PRIORITY_FIELD_ID", value: {singleSelectOptionId: "$PRIORITY_OPTION_ID"}}) {
    projectV2Item {
      id
    }
  }
}
EOF
)
      gh api graphql -f query="$UPDATE_QUERY" > /dev/null
      echo "  ✓ Priority set to: $priority"
    fi
  fi

  # Req Type
  if [ -n "$REQ_TYPE_FIELD_ID" ] && [ "$REQ_TYPE_FIELD_ID" != "null" ]; then
    REQ_TYPE_OPTION_ID=$(get_option_id "Req Type" "$req_type")
    if [ -n "$REQ_TYPE_OPTION_ID" ] && [ "$REQ_TYPE_OPTION_ID" != "null" ]; then
      UPDATE_QUERY=$(cat <<EOF
mutation {
  updateProjectV2ItemFieldValue(input: {projectId: "$PROJECT_ID", itemId: "$ITEM_ID", fieldId: "$REQ_TYPE_FIELD_ID", value: {singleSelectOptionId: "$REQ_TYPE_OPTION_ID"}}) {
    projectV2Item {
      id
    }
  }
}
EOF
)
      gh api graphql -f query="$UPDATE_QUERY" > /dev/null
      echo "  ✓ Req Type set to: $req_type"
    fi
  fi

  # NFR Category
  if [ -n "$NFR_CATEGORY_FIELD_ID" ] && [ "$NFR_CATEGORY_FIELD_ID" != "null" ] && [ "$nfr_category" != "N/A" ]; then
    NFR_OPTION_ID=$(get_option_id "NFR Category" "$nfr_category")
    if [ -n "$NFR_OPTION_ID" ] && [ "$NFR_OPTION_ID" != "null" ]; then
      UPDATE_QUERY=$(cat <<EOF
mutation {
  updateProjectV2ItemFieldValue(input: {projectId: "$PROJECT_ID", itemId: "$ITEM_ID", fieldId: "$NFR_CATEGORY_FIELD_ID", value: {singleSelectOptionId: "$NFR_OPTION_ID"}}) {
    projectV2Item {
      id
    }
  }
}
EOF
)
      gh api graphql -f query="$UPDATE_QUERY" > /dev/null
      echo "  ✓ NFR Category set to: $nfr_category"
    fi
  fi

  # Epic (text field)
  if [ -n "$EPIC_FIELD_ID" ] && [ "$EPIC_FIELD_ID" != "null" ]; then
    UPDATE_QUERY=$(cat <<EOF
mutation {
  updateProjectV2ItemFieldValue(input: {projectId: "$PROJECT_ID", itemId: "$ITEM_ID", fieldId: "$EPIC_FIELD_ID", value: {text: "$epic"}}) {
    projectV2Item {
      id
    }
  }
}
EOF
)
    gh api graphql -f query="$UPDATE_QUERY" > /dev/null
    echo "  ✓ Epic set to: $epic"
  fi

  # Story Points (number field)
  if [ -n "$STORY_POINTS_FIELD_ID" ] && [ "$STORY_POINTS_FIELD_ID" != "null" ]; then
    UPDATE_QUERY=$(cat <<EOF
mutation {
  updateProjectV2ItemFieldValue(input: {projectId: "$PROJECT_ID", itemId: "$ITEM_ID", fieldId: "$STORY_POINTS_FIELD_ID", value: {number: $story_points}}) {
    projectV2Item {
      id
    }
  }
}
EOF
)
    gh api graphql -f query="$UPDATE_QUERY" > /dev/null
    echo "  ✓ Story Points set to: $story_points"
  fi

  # Source (text field)
  if [ -n "$SOURCE_FIELD_ID" ] && [ "$SOURCE_FIELD_ID" != "null" ]; then
    # Escape source string for GraphQL
    SOURCE_ESCAPED=$(echo "$source" | sed 's/"/\\"/g')
    UPDATE_QUERY=$(cat <<EOF
mutation {
  updateProjectV2ItemFieldValue(input: {projectId: "$PROJECT_ID", itemId: "$ITEM_ID", fieldId: "$SOURCE_FIELD_ID", value: {text: "$SOURCE_ESCAPED"}}) {
    projectV2Item {
      id
    }
  }
}
EOF
)
    gh api graphql -f query="$UPDATE_QUERY" > /dev/null
    echo "  ✓ Source set"
  fi

  # Clarification Status
  if [ -n "$CLARIFICATION_STATUS_FIELD_ID" ] && [ "$CLARIFICATION_STATUS_FIELD_ID" != "null" ]; then
    STATUS_OPTION_ID=$(get_option_id "Clarification Status" "$clarification_status")
    if [ -n "$STATUS_OPTION_ID" ] && [ "$STATUS_OPTION_ID" != "null" ]; then
      UPDATE_QUERY=$(cat <<EOF
mutation {
  updateProjectV2ItemFieldValue(input: {projectId: "$PROJECT_ID", itemId: "$ITEM_ID", fieldId: "$CLARIFICATION_STATUS_FIELD_ID", value: {singleSelectOptionId: "$STATUS_OPTION_ID"}}) {
    projectV2Item {
      id
    }
  }
}
EOF
)
      gh api graphql -f query="$UPDATE_QUERY" > /dev/null
      echo "  ✓ Clarification Status set to: $clarification_status"
    fi
  fi

  # Confidence
  if [ -n "$CONFIDENCE_FIELD_ID" ] && [ "$CONFIDENCE_FIELD_ID" != "null" ]; then
    CONFIDENCE_OPTION_ID=$(get_option_id "Confidence" "$confidence")
    if [ -n "$CONFIDENCE_OPTION_ID" ] && [ "$CONFIDENCE_OPTION_ID" != "null" ]; then
      UPDATE_QUERY=$(cat <<EOF
mutation {
  updateProjectV2ItemFieldValue(input: {projectId: "$PROJECT_ID", itemId: "$ITEM_ID", fieldId: "$CONFIDENCE_FIELD_ID", value: {singleSelectOptionId: "$CONFIDENCE_OPTION_ID"}}) {
    projectV2Item {
      id
    }
  }
}
EOF
)
      gh api graphql -f query="$UPDATE_QUERY" > /dev/null
      echo "  ✓ Confidence set to: $confidence"
    fi
  fi

  echo "✓ Issue #$issue_number complete"
  echo ""
}

# Update all issues
add_and_update_issue 5 "P0" "Non-Functional" "Compliance" "Non-Functional Requirements" 8 "docs/account-requirements.md - Section 8: Non-Functional Requirements (Compliance)" "Confirmed" "Firm"

add_and_update_issue 6 "P0" "Non-Functional" "Reliability" "Non-Functional Requirements" 13 "docs/account-requirements.md - Section 8: Non-Functional Requirements (Consistency)" "Confirmed" "Firm"

add_and_update_issue 7 "P0" "Non-Functional" "Reliability" "Non-Functional Requirements" 13 "docs/account-requirements.md - Section 8: Non-Functional Requirements (Availability and Backups)" "Confirmed" "Firm"

add_and_update_issue 8 "P0" "Non-Functional" "Performance" "Non-Functional Requirements" 8 "docs/account-requirements.md - Section 8: Non-Functional Requirements (Performance)" "Confirmed" "Firm"

add_and_update_issue 9 "P0" "Functional" "N/A" "Account Lifecycle" 8 "docs/account-requirements.md - Section 1: Account Creation" "Confirmed" "Firm"

add_and_update_issue 10 "P0" "Functional" "N/A" "Account Lifecycle" 5 "docs/account-requirements.md - Section 2: Account Profile Management (Customer)" "Confirmed" "Firm"

add_and_update_issue 11 "P0" "Non-Functional" "Security" "Non-Functional Requirements" 13 "docs/account-requirements.md - Section 8: Non-Functional Requirements (Security)" "Confirmed" "Firm"

add_and_update_issue 12 "P0" "Functional" "N/A" "Account Lifecycle" 8 "docs/account-requirements.md - Section 3: Deposits and Withdrawals" "Confirmed" "Firm"

add_and_update_issue 13 "P1" "Functional" "N/A" "Account Lifecycle" 13 "docs/account-requirements.md - Section 4: Transfers" "Confirmed" "Firm"

add_and_update_issue 14 "P1" "Functional" "N/A" "Account Lifecycle" 5 "docs/account-requirements.md - Section 5: Freeze / Close / Reopen" "Confirmed" "Firm"

add_and_update_issue 15 "P1" "Functional" "N/A" "Account Lifecycle" 8 "docs/account-requirements.md - Section 6: Transaction History / Statements" "Confirmed" "Firm"

add_and_update_issue 16 "P1" "Functional" "N/A" "Account Lifecycle" 8 "docs/account-requirements.md - Section 7: Notifications" "Confirmed" "Firm"

echo "All issues updated!"
