"""
Universal Requirements → GitHub Issues Pipeline

Supported input formats:
  - Audio:       .mp3, .wav, .m4a, .ogg, .flac, .webm
  - Structured:  .json, .csv, .xlsx, .xls
  - Text:        .txt, .md

Usage:
  Single file:    python import_to_issues.py path/to/file.csv
  Multiple files: python import_to_issues.py file1.csv file2.mp3 file3.json
  Folder:         python import_to_issues.py path/to/folder/
  Mixed:          python import_to_issues.py file1.csv path/to/folder/ file2.mp3

Dependencies:
  pip install anthropic python-dotenv requests pandas openpyxl openai-whisper
  Windows audio: download ffmpeg from https://ffmpeg.org/download.html and add to PATH
"""

import sys
import os
import json
import csv
import re
import requests
import urllib3
import pandas as pd
from pathlib import Path
import anthropic
from dotenv import load_dotenv

load_dotenv()

# ── SSL: disable verification warnings on corporate networks ─────────────────
# If you have a proper cert bundle, set REQUESTS_CA_BUNDLE in your .env instead
_ca_bundle = os.environ.get("REQUESTS_CA_BUNDLE")
SSL_VERIFY = _ca_bundle if _ca_bundle else False
if not SSL_VERIFY:
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

import httpx
_ca_bundle = os.environ.get("REQUESTS_CA_BUNDLE")
claude = anthropic.Anthropic(
    api_key=os.environ["ANTHROPIC_API_KEY"],
    http_client=httpx.Client(verify=_ca_bundle if _ca_bundle else False),
)
GH_TOKEN   = os.environ["GITHUB_TOKEN"]
GH_OWNER   = os.environ["GITHUB_OWNER"]
GH_REPO    = os.environ["GITHUB_REPO"]
GH_HEADERS = {
    "Authorization": f"Bearer {GH_TOKEN}",
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
}

AUDIO_EXTENSIONS      = {".mp3", ".wav", ".m4a", ".ogg", ".flac", ".webm"}
STRUCTURED_EXTENSIONS = {".json", ".csv", ".xlsx", ".xls"}
TEXT_EXTENSIONS       = {".txt", ".md"}
ALL_EXTENSIONS        = AUDIO_EXTENSIONS | STRUCTURED_EXTENSIONS | TEXT_EXTENSIONS

# ── Field validation ──────────────────────────────────────────────────────────

VALID = {
    "requirement_type":     {"Functional", "Non-Functional", "Unclear"},
    "nfr_category":         {"Performance", "Security", "Usability", "Reliability",
                             "Scalability", "Compliance", "Maintainability", "N/A"},
    "priority":             {"P0", "P1", "P2"},
    "clarification_status": {"Needs Client Input", "Needs Clarification", "Confirmed"},
    "confidence":           {"Firm", "Assumed", "Guess"},
}

DEFAULTS = {
    "requirement_type":     "Unclear",
    "nfr_category":         "N/A",
    "priority":             "P2",
    "story_points":         1,
    "source":               "Imported file",
    "clarification_status": "Needs Clarification",
    "confidence":           "Guess",
    "acceptance_criteria":  [],
    "description":          "",
}

def validate_req(req: dict, source_hint: str) -> dict:
    out = {**DEFAULTS, **req}
    try:
        out["story_points"] = int(float(str(out.get("story_points", 1))))
    except (ValueError, TypeError):
        out["story_points"] = 1
    for field, valid_set in VALID.items():
        val = str(out.get(field, "")).strip()
        if val not in valid_set:
            print(f"      ⚠ Invalid {field} value '{val}', defaulting to '{DEFAULTS[field]}'")
            out[field] = DEFAULTS[field]
    if out["requirement_type"] == "Functional":
        out["nfr_category"] = "N/A"
    if isinstance(out["acceptance_criteria"], str):
        out["acceptance_criteria"] = [
            line.strip("- []").strip()
            for line in out["acceptance_criteria"].splitlines()
            if line.strip()
        ]
    if not out.get("source") or out["source"] == DEFAULTS["source"]:
        out["source"] = source_hint
    return out

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 — INGEST
# ══════════════════════════════════════════════════════════════════════════════

def ingest_audio(path: Path) -> str:
    # Check for ffmpeg before attempting transcription
    import shutil
    if not shutil.which("ffmpeg"):
        raise EnvironmentError(
            "ffmpeg is not installed or not on your PATH.\n"
            "  Windows: download from https://ffmpeg.org/download.html\n"
            "           extract the zip, and add the /bin folder to your system PATH.\n"
            "  Then restart your terminal and try again."
        )

    import whisper
    print(f"  → Transcribing audio with local Whisper ...")
    model  = whisper.load_model("base")
    result = model.transcribe(str(path))
    text   = result["text"]
    print(f"  → Transcription complete ({len(text)} chars).")
    return text

def ingest_text(path: Path) -> str:
    print(f"  → Reading plain text ...")
    return path.read_text(encoding="utf-8")

def ingest_json(path: Path) -> dict | str:
    print(f"  → Parsing JSON ...")
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, dict) and "epics" in data:
        return data
    if isinstance(data, list):
        return {"epics": [{"title": "Imported", "description": "Auto-grouped from flat list", "requirements": data}]}
    print(f"  → Unrecognized JSON shape, sending to Claude for extraction ...")
    return json.dumps(data)

def ingest_csv(path: Path) -> dict:
    print(f"  → Parsing CSV ...")
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(normalise_row(row))
    return {"epics": rows_to_epics(rows)}

def ingest_excel(path: Path) -> dict:
    print(f"  → Parsing Excel workbook ...")
    xl       = pd.ExcelFile(path)
    all_rows = []
    for sheet in xl.sheet_names:
        df         = xl.parse(sheet)
        df.columns = [slugify(c) for c in df.columns]
        for _, row in df.iterrows():
            r           = {k: ("" if pd.isna(v) else str(v)) for k, v in row.items()}
            r["_sheet"] = sheet
            all_rows.append(normalise_row(r))
    return {"epics": rows_to_epics(all_rows)}

# ── Helpers for structured formats ───────────────────────────────────────────

COLUMN_ALIASES = {
    "requirement_type": "requirement_type", "req_type": "requirement_type", "type": "requirement_type",
    "nfr_category":     "nfr_category",     "nfr":      "nfr_category",
    "priority":         "priority",
    "story_points":     "story_points",      "points":   "story_points",   "sp": "story_points",
    "source":           "source",
    "clarification_status": "clarification_status", "clarification": "clarification_status",
    "confidence":       "confidence",
    "description":      "description",       "desc":     "description",
    "acceptance_criteria": "acceptance_criteria", "acceptance": "acceptance_criteria", "ac": "acceptance_criteria",
    "title":            "title",             "name":     "title",          "requirement": "title",
    "epic":             "epic",              "epic_title": "epic",         "group": "epic", "_sheet": "epic",
}

def slugify(col: str) -> str:
    return re.sub(r"\s+", "_", col.strip().lower())

def normalise_row(row: dict) -> dict:
    out = {}
    for raw_key, val in row.items():
        canonical = COLUMN_ALIASES.get(slugify(raw_key))
        if canonical:
            out[canonical] = str(val).strip() if val is not None else ""
    return out

def rows_to_epics(rows: list[dict]) -> list[dict]:
    groups: dict[str, list] = {}
    for row in rows:
        epic_name = row.pop("epic", None) or "Imported Requirements"
        groups.setdefault(epic_name, []).append(row)
    return [
        {"title": name, "description": f"Requirements imported under epic: {name}", "requirements": reqs}
        for name, reqs in groups.items()
    ]

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 — EXTRACT via Claude
# ══════════════════════════════════════════════════════════════════════════════

SYSTEM_PROMPT = """
You are a business analyst assistant. Given text (a meeting transcript, notes,
or requirements document), extract all epics and their associated requirements.

Return ONLY valid JSON in this exact shape — no markdown, no explanation,
no code fences, no text before or after the JSON:
{
  "epics": [
    {
      "title": "Short epic name",
      "description": "What this epic covers",
      "requirements": [
        {
          "title": "One-line requirement title",
          "description": "Plain language description of the requirement.",
          "acceptance_criteria": ["criterion 1", "criterion 2"],
          "requirement_type": "Functional | Non-Functional | Unclear",
          "nfr_category": "Performance | Security | Usability | Reliability | Scalability | Compliance | Maintainability | N/A",
          "priority": "P0 | P1 | P2",
          "story_points": 3,
          "source": "inferred from content",
          "clarification_status": "Needs Client Input | Needs Clarification | Confirmed",
          "confidence": "Firm | Assumed | Guess"
        }
      ]
    }
  ]
}

Rules:
- nfr_category must be "N/A" for Functional requirements.
- story_points must be an integer (1, 2, 3, 5, 8, 13).
- confidence reflects how clearly the requirement was stated.
- Every requirement MUST have all fields populated.
- YOUR RESPONSE MUST START WITH { AND END WITH }. NO OTHER TEXT.
"""

def extract_via_claude(raw_text: str, source_hint: str, retries: int = 2) -> dict:
    print(f"  → Extracting structure via Claude ...")
    last_error = None

    for attempt in range(1, retries + 2):
        if attempt > 1:
            print(f"  → Retry {attempt - 1}/{retries} ...")

        message = claude.messages.create(
            model="claude-opus-4-5",
            max_tokens=4096,
            system=SYSTEM_PROMPT,
            messages=[
                {"role": "user", "content": f"Source: {source_hint}\n\n{raw_text}"}
            ],
        )

        raw = message.content[0].text.strip()

        # Strip accidental markdown code fences if present
        if raw.startswith("```"):
            raw = re.sub(r"^```[a-z]*\n?", "", raw)
            raw = re.sub(r"\n?```$", "", raw)
            raw = raw.strip()

        try:
            data = json.loads(raw)
            print(f"  → Claude returned {len(data.get('epics', []))} epic(s).")
            return data
        except json.JSONDecodeError as e:
            last_error = e
            print(f"  ⚠ Claude response was not valid JSON (attempt {attempt}): {e}")
            print(f"  ⚠ Raw response preview: {raw[:200]!r}")

    raise ValueError(f"Claude failed to return valid JSON after {retries + 1} attempts. Last error: {last_error}")

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 — CREATE ISSUES
# ══════════════════════════════════════════════════════════════════════════════

def create_issue(title: str, body: str, labels: list[str]) -> dict:
    resp = requests.post(
        f"https://api.github.com/repos/{GH_OWNER}/{GH_REPO}/issues",
        headers=GH_HEADERS,
        json={"title": title, "body": body, "labels": labels},
        verify=SSL_VERIFY,
    )
    resp.raise_for_status()
    return resp.json()

def add_sub_issue(parent_number: int, sub_issue_id: int) -> None:
    resp = requests.post(
        f"https://api.github.com/repos/{GH_OWNER}/{GH_REPO}/issues/{parent_number}/sub_issues",
        headers=GH_HEADERS,
        json={"sub_issue_id": sub_issue_id},
        verify=SSL_VERIFY,
    )
    resp.raise_for_status()

def build_epic_body(epic: dict) -> str:
    return f"## Summary\n\n{epic['description']}\n"

def build_requirement_body(req: dict) -> str:
    ac = "\n".join(f"- [ ] {c}" for c in req.get("acceptance_criteria", []))
    return f"""### Description

{req['description']}

### Acceptance Criteria

{ac if ac else '_No response_'}

### Requirement Type

{req['requirement_type']}

### NFR Category

{req['nfr_category']}

### Priority

{req['priority']}

### Story Points

{req['story_points']}

### Source

{req['source']}

### Clarification Status

{req['clarification_status']}

### Confidence

{req['confidence']}
"""

def create_all_issues(data: dict, source_hint: str) -> None:
    total_reqs = sum(len(e.get("requirements", [])) for e in data["epics"])
    print(f"      {len(data['epics'])} epic(s), {total_reqs} requirement(s)\n")

    for epic in data["epics"]:
        epic_issue  = create_issue(
            title=f"[EPIC]: {epic['title']}",
            body=build_epic_body(epic),
            labels=["epic"],
        )
        epic_number = epic_issue["number"]
        print(f"  [EPIC] #{epic_number}: {epic['title']}")
        print(f"         {epic_issue['html_url']}")

        for req in epic.get("requirements", []):
            req        = validate_req(req, source_hint)
            req_issue  = create_issue(
                title=f"[REQ]: {req['title']}",
                body=build_requirement_body(req),
                labels=["requirement"],
            )
            req_number = req_issue["number"]
            req_id     = req_issue["id"]
            add_sub_issue(epic_number, req_id)
            print(f"    [REQ] #{req_number}: {req['title']}")
            print(f"           {req_issue['html_url']}")

# ══════════════════════════════════════════════════════════════════════════════
# FILE RESOLUTION
# ══════════════════════════════════════════════════════════════════════════════

def resolve_files(args: list[str]) -> list[Path]:
    found  = []
    errors = []

    for arg in args:
        p = Path(arg)
        if not p.exists():
            errors.append(f"  ✗ Not found: {arg}")
            continue
        if p.is_dir():
            matches = sorted([f for f in p.rglob("*") if f.suffix.lower() in ALL_EXTENSIONS])
            if not matches:
                errors.append(f"  ✗ No supported files found in folder: {arg}")
            else:
                found.extend(matches)
        elif p.is_file():
            if p.suffix.lower() not in ALL_EXTENSIONS:
                errors.append(f"  ✗ Unsupported file type: {arg}")
            else:
                found.append(p)

    if errors:
        print("\nWarnings:")
        for e in errors:
            print(e)
        print()

    seen   = set()
    unique = []
    for f in found:
        resolved = f.resolve()
        if resolved not in seen:
            seen.add(resolved)
            unique.append(f)

    return unique

# ══════════════════════════════════════════════════════════════════════════════
# PER-FILE PROCESSOR
# ══════════════════════════════════════════════════════════════════════════════

def process_file(path: Path) -> None:
    ext         = path.suffix.lower()
    source_hint = f"Imported from {path.name}"

    print(f"\n{'='*60}")
    print(f"  File:   {path}")
    print(f"  Format: {ext}")
    print(f"{'='*60}")

    print("\n[1/3] Ingesting ...")
    if ext in AUDIO_EXTENSIONS:
        intermediate = ingest_audio(path)
    elif ext == ".json":
        intermediate = ingest_json(path)
    elif ext == ".csv":
        intermediate = ingest_csv(path)
    elif ext in {".xlsx", ".xls"}:
        intermediate = ingest_excel(path)
    elif ext in TEXT_EXTENSIONS:
        intermediate = ingest_text(path)

    print("\n[2/3] Extracting requirements ...")
    if isinstance(intermediate, str):
        data = extract_via_claude(intermediate, source_hint)
    else:
        print(f"  → Structured data detected, skipping Claude extraction.")
        data = intermediate

    print(f"\n[3/3] Creating GitHub issues ...")
    create_all_issues(data, source_hint)

# ══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════

def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  Single file:    python import_to_issues.py file.csv")
        print("  Multiple files: python import_to_issues.py file1.csv file2.mp3 file3.json")
        print("  Folder:         python import_to_issues.py path/to/folder/")
        print("  Mixed:          python import_to_issues.py file1.csv path/to/folder/ file2.mp3")
        print(f"\nSupported types: {', '.join(sorted(ALL_EXTENSIONS))}")
        sys.exit(1)

    files = resolve_files(sys.argv[1:])

    if not files:
        print("No supported files found. Exiting.")
        sys.exit(1)

    print(f"\nFiles to process ({len(files)}):")
    for f in files:
        print(f"  • {f}")

    results = {"success": [], "failed": []}

    for i, file in enumerate(files, 1):
        print(f"\n── File {i} of {len(files)} ──────────────────────────────────────")
        try:
            process_file(file)
            results["success"].append(file)
        except Exception as e:
            print(f"\n  ✗ Failed to process {file.name}: {e}")
            results["failed"].append((file, str(e)))

    print(f"\n{'='*60}")
    print(f"  SUMMARY")
    print(f"{'='*60}")
    print(f"  ✓ Succeeded: {len(results['success'])}")
    for f in results["success"]:
        print(f"      • {f.name}")
    if results["failed"]:
        print(f"  ✗ Failed:    {len(results['failed'])}")
        for f, err in results["failed"]:
            print(f"      • {f.name} — {err}")
    print(f"\n  Project fields will be set automatically by the GitHub Actions workflow.")

if __name__ == "__main__":
    main()