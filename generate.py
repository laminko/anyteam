#!/usr/bin/env python3
"""
generate.py — author-time generator for the portable hub-and-spoke team.

Schema contract (src/harnesses.json):
  version          int     schema version (currently 1)
  model_tiers      object  global fallback: {"heavy": "<id>", "light": "<id>"}
  harnesses        object  keyed by harness id
    <id>:
      label              str
      instruction_file   str   filename of the rendered manual inside the dist root
      roster:
        shape  str   currently only "md-frontmatter" supported
        dir    str   subdirectory under dist root where agent files are written
        scope  str   informational only
      model_map          object  {"heavy": "<model-id>", "light": "<model-id>"}
      frontmatter_order  list    ordered list of native keys to emit
      static_frontmatter object  (optional) key → literal value to emit for "static" source
      key_map            object  native-key → source or special token
                                 "id"            → role id string
                                 "description"   → role description string
                                 "<model_map>"   → resolve via model_map[model_tier]
                                 "<tool_policy>" → resolve via tool_policy_map[tool_policy][native_key]
                                 "static"        → emit from static_frontmatter[native_key]
      tool_policy_map    object  keyed by tool_policy value
                                 {}              → omit all <tool_policy> keys
                                 {key: "omit"}   → omit this key (backward compat sentinel)
                                 {key: bool}     → emit as YAML bool (true/false)
                                 {key: [...]}    → emit as YAML inline list or block list
                                 {key: {...}}    → emit as YAML block map
      delegation_snippet str    filename under src/snippets/ to splice into the manual

CLI:
  python3 generate.py                  render all harnesses
  python3 generate.py --harness <id>   render one harness
  python3 generate.py --check          render to memory, diff vs committed dist/, exit 1 on drift
"""

import json
import os
import sys
import difflib

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.join(REPO_ROOT, "src")
DIST_DIR = os.path.join(REPO_ROOT, "dist")

HARNESSES_JSON = os.path.join(SRC_DIR, "harnesses.json")
ROLES_DIR = os.path.join(SRC_DIR, "roles")
SNIPPETS_DIR = os.path.join(SRC_DIR, "snippets")
MANUAL_SRC = os.path.join(SRC_DIR, "manual.md")

# Deterministic role iteration order — do NOT rely on glob/fs order.
ROLE_ORDER = ["pm", "architect", "be", "fe", "uiux-audit", "uiux-research"]

VALID_MODEL_TIERS = {"heavy", "light"}
VALID_TOOL_POLICIES = {"full", "read-only", "research", "audit"}

# ---------------------------------------------------------------------------
# Frontmatter parser
# ---------------------------------------------------------------------------

def parse_role_file(path):
    """Parse a src/roles/*.md file into (meta dict, body str).

    Frontmatter is the YAML block between the first '---' and the next '---'.
    Only flat keys and folded scalars (description: >) are handled — no need
    for a full YAML parser given the constrained schema.

    Returns:
        (meta, body) where meta is a dict with keys:
            id, display_name, description, model_tier, tool_policy
        and body is the text after the closing '---' (leading newline stripped).
    """
    with open(path, "r", encoding="utf-8") as fh:
        raw = fh.read()

    if not raw.startswith("---"):
        raise ValueError(f"{path}: does not start with '---'")

    # Find closing ---
    rest = raw[3:]  # strip leading ---
    end = rest.find("\n---")
    if end == -1:
        raise ValueError(f"{path}: no closing '---' found")

    fm_text = rest[:end]
    body = rest[end + 4:]  # skip \n---
    if body.startswith("\n"):
        body = body[1:]

    meta = _parse_flat_yaml(fm_text, path)
    return meta, body


def _parse_flat_yaml(text, source_path):
    """Minimal flat YAML parser supporting:
      key: simple value
      key: >
        continuation line 1
        continuation line 2
    """
    meta = {}
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.strip().startswith("#"):
            i += 1
            continue
        if ":" not in line:
            i += 1
            continue
        colon = line.index(":")
        key = line[:colon].strip()
        value_part = line[colon + 1:].strip()

        if value_part == ">":
            # Folded scalar: gather indented continuation lines
            parts = []
            i += 1
            while i < len(lines) and (lines[i].startswith(" ") or lines[i].startswith("\t")):
                parts.append(lines[i].strip())
                i += 1
            meta[key] = " ".join(parts)
        else:
            meta[key] = value_part
            i += 1

    return meta


def validate_meta(meta, path):
    required = ["id", "display_name", "description", "model_tier", "tool_policy"]
    for k in required:
        if k not in meta:
            raise ValueError(f"{path}: missing required frontmatter key '{k}'")
    if meta["model_tier"] not in VALID_MODEL_TIERS:
        raise ValueError(
            f"{path}: model_tier='{meta['model_tier']}' not in {VALID_MODEL_TIERS}"
        )
    if meta["tool_policy"] not in VALID_TOOL_POLICIES:
        raise ValueError(
            f"{path}: tool_policy='{meta['tool_policy']}' not in {VALID_TOOL_POLICIES}"
        )
    # Defense-in-depth: keep id path/identifier-safe and description single-line, so
    # neither can escape the generated path or inject sibling frontmatter keys.
    _idset = "abcdefghijklmnopqrstuvwxyz0123456789-"
    if not meta["id"] or meta["id"][0] == "-" or any(c not in _idset for c in meta["id"]):
        raise ValueError(
            f"{path}: id='{meta['id']}' must be lowercase letters/digits/'-' (no leading '-')"
        )
    if "\n" in meta["description"] or "\r" in meta["description"]:
        raise ValueError(f"{path}: description must be a single line (no newlines)")


# ---------------------------------------------------------------------------
# YAML value serializers (hand-rolled, stdlib only)
# ---------------------------------------------------------------------------

def _yaml_scalar(value):
    """Serialize a Python str/bool/int as a YAML scalar (unquoted when safe)."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    s = str(value)
    # Quote if the string contains characters that could confuse YAML parsers,
    # or if it would be misread as a special type (true/false/null/numbers).
    _safe_re_chars = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
                         "0123456789_-./: @()")
    if s.lower() in ("true", "false", "null", "yes", "no", "on", "off", "~"):
        return f'"{s}"'
    if all(c in _safe_re_chars for c in s) and s:
        return s
    # Fall back to double-quoted with minimal escaping
    escaped = s.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def _yaml_inline_list(items):
    """Serialize a list as YAML inline: [A, B, C]"""
    return "[" + ", ".join(_yaml_scalar(i) for i in items) + "]"


def _yaml_block_map(d, indent=2):
    """Serialize a dict as a YAML block map at the given indent level."""
    prefix = " " * indent
    lines = []
    for k, v in d.items():
        if isinstance(v, bool):
            lines.append(f"{prefix}{k}: {'true' if v else 'false'}")
        elif isinstance(v, list):
            lines.append(f"{prefix}{k}: {_yaml_inline_list(v)}")
        elif isinstance(v, dict):
            lines.append(f"{prefix}{k}:")
            lines.extend(_yaml_block_map(v, indent + 2).splitlines())
        else:
            lines.append(f"{prefix}{k}: {_yaml_scalar(v)}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Emitters
# ---------------------------------------------------------------------------

def render_agent_file(meta, body, harness_cfg):
    """Render a single agent file as a string (frontmatter + body).

    The emitter is fully data-driven from:
      frontmatter_order, key_map, model_map, tool_policy_map, static_frontmatter

    Supported key_map value directives:
      "id"            → meta["id"]
      "description"   → meta["description"]
      "<model_map>"   → model_map[meta["model_tier"]]
      "<tool_policy>" → tool_policy_map[meta["tool_policy"]][native_key]
                        (may contribute multiple frontmatter keys; each resolved
                         individually as the key appears in frontmatter_order)
      "static"        → static_frontmatter[native_key]

    Any key whose resolved value is absent (key not in policy dict, or "omit"
    sentinel) is silently skipped.
    """
    model_map = harness_cfg["model_map"]
    tool_policy_map = harness_cfg["tool_policy_map"]
    frontmatter_order = harness_cfg["frontmatter_order"]
    key_map = harness_cfg["key_map"]
    static_frontmatter = harness_cfg.get("static_frontmatter", {})

    policy = meta["tool_policy"]
    policy_def = tool_policy_map.get(policy, {})

    lines = ["---"]
    for native_key in frontmatter_order:
        source = key_map.get(native_key)
        if source is None:
            continue

        if source == "id":
            # Emit raw (role ids are simple identifiers, never need quoting)
            lines.append(f"{native_key}: {meta['id']}")

        elif source == "description":
            # Emit raw — descriptions are long prose; original generator never quoted them
            lines.append(f"{native_key}: {meta['description']}")

        elif source == "<model_map>":
            value = model_map[meta["model_tier"]]
            # Emit raw — model ids are slash-separated identifiers, never need quoting
            lines.append(f"{native_key}: {value}")

        elif source == "<tool_policy>":
            if native_key not in policy_def:
                # Key absent from this policy — skip it
                continue
            val = policy_def[native_key]
            if val == "omit":
                # Backward-compat sentinel: skip
                continue
            elif isinstance(val, bool):
                lines.append(f"{native_key}: {'true' if val else 'false'}")
            elif isinstance(val, list):
                # Emit as YAML inline list (matches Phase-1 claude-code style)
                lines.append(f"{native_key}: {_yaml_inline_list(val)}")
            elif isinstance(val, dict):
                # Emit as a YAML block map
                lines.append(f"{native_key}:")
                lines.append(_yaml_block_map(val, indent=2))
            else:
                lines.append(f"{native_key}: {_yaml_scalar(val)}")

        elif source == "static":
            if native_key not in static_frontmatter:
                continue
            val = static_frontmatter[native_key]
            if isinstance(val, bool):
                lines.append(f"{native_key}: {'true' if val else 'false'}")
            elif isinstance(val, list):
                lines.append(f"{native_key}: {_yaml_inline_list(val)}")
            elif isinstance(val, dict):
                lines.append(f"{native_key}:")
                lines.append(_yaml_block_map(val, indent=2))
            else:
                lines.append(f"{native_key}: {_yaml_scalar(val)}")

        else:
            # Plain source key from meta (legacy: e.g. source == "id", "description"
            # handled above; any unrecognized source is treated as a meta key lookup)
            value = meta.get(source, "")
            if value:
                lines.append(f"{native_key}: {_yaml_scalar(value)}")

    lines.append("---")
    lines.append("")
    fm_block = "\n".join(lines)

    # Ensure body ends with exactly one newline
    content = fm_block + body
    content = content.rstrip("\n") + "\n"
    return content


def _toml_basic_string(s):
    """Serialize s as a TOML basic string (double-quoted, inline).

    Escapes: \\ then " (only those two are needed for TOML basic strings
    that do not contain control characters — role descriptions/ids are plain prose).
    """
    escaped = s.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def _toml_multiline_string(s):
    """Serialize s as a TOML basic multi-line string.

    Delimited by triple double-quotes. TOML trims the first newline after the
    opening delimiter, so we open on one line and start the content on the next.
    The loaded value will therefore start at the body's first character.

    Escaping applied to body: \\ → \\\\ then \"\"\" → \\\"\\\"\\\".
    """
    escaped = s.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
    return '"""\n' + escaped + '"""'


def render_agent_file_toml(meta, body, harness_cfg):
    """Render a single agent file as a TOML string.

    Keys are emitted in toml_order. Mapping:
      name                    → meta["id"]
      description             → meta["description"]  (basic string)
      model                   → model_map[meta["model_tier"]]
      model_reasoning_effort  → reasoning_effort_map[meta["model_tier"]]
      sandbox_mode            → tool_policy_map[meta["tool_policy"]]["sandbox_mode"]
      developer_instructions  → body  (multiline basic string)
    """
    model_map = harness_cfg["model_map"]
    reasoning_effort_map = harness_cfg["reasoning_effort_map"]
    tool_policy_map = harness_cfg["tool_policy_map"]
    toml_order = harness_cfg["toml_order"]

    policy = meta["tool_policy"]
    policy_def = tool_policy_map.get(policy, {})

    tier = meta["model_tier"]

    lines = []
    for key in toml_order:
        if key == "name":
            lines.append(f"name = {_toml_basic_string(meta['id'])}")
        elif key == "description":
            lines.append(f"description = {_toml_basic_string(meta['description'])}")
        elif key == "model":
            lines.append(f"model = {_toml_basic_string(model_map[tier])}")
        elif key == "model_reasoning_effort":
            lines.append(f"model_reasoning_effort = {_toml_basic_string(reasoning_effort_map[tier])}")
        elif key == "sandbox_mode":
            if "sandbox_mode" in policy_def:
                lines.append(f"sandbox_mode = {_toml_basic_string(policy_def['sandbox_mode'])}")
        elif key == "developer_instructions":
            lines.append(f"developer_instructions = {_toml_multiline_string(body)}")

    content = "\n".join(lines)
    content = content.rstrip("\n") + "\n"
    return content


def render_manual(harness_cfg):
    """Render src/manual.md with delegation block and model note spliced in."""
    with open(MANUAL_SRC, "r", encoding="utf-8") as fh:
        manual = fh.read()

    # (a) BLOCK splice: replace <!-- BEGIN:DELEGATION -->...<!-- END:DELEGATION -->
    snippet_file = os.path.join(SNIPPETS_DIR, harness_cfg["delegation_snippet"])
    with open(snippet_file, "r", encoding="utf-8") as fh:
        snippet = fh.read().strip()

    begin_tag = "<!-- BEGIN:DELEGATION -->"
    end_tag = "<!-- END:DELEGATION -->"
    b_idx = manual.find(begin_tag)
    e_idx = manual.find(end_tag)
    if b_idx == -1 or e_idx == -1:
        raise ValueError("manual.md: delegation markers not found")
    # Replace from begin tag through end tag (inclusive) with snippet contents only
    manual = manual[:b_idx] + snippet + "\n" + manual[e_idx + len(end_tag):]

    # (b) INLINE splice: replace <!-- BEGIN:MODELNOTE --><!-- END:MODELNOTE -->
    model_map = harness_cfg["model_map"]
    heavy = model_map["heavy"]
    light = model_map["light"]
    if heavy == "inherit":
        note = (
            "> On this harness, agents inherit your selected model"
            " (per-agent tiering isn't enforced — set it in the UI if desired)."
        )
    else:
        note = (
            f"> On this harness, the **heavy** tier = `{heavy}`,"
            f" the **light** tier = `{light}`."
        )
    inline_marker = "<!-- BEGIN:MODELNOTE --><!-- END:MODELNOTE -->"
    if inline_marker not in manual:
        raise ValueError("manual.md: inline modelnote marker not found")
    manual = manual.replace(inline_marker, note)

    manual = manual.rstrip("\n") + "\n"
    return manual


# ---------------------------------------------------------------------------
# Main render logic
# ---------------------------------------------------------------------------

def load_roles():
    """Load and validate all roles in ROLE_ORDER. Returns list of (meta, body)."""
    roles = []
    for role_id in ROLE_ORDER:
        path = os.path.join(ROLES_DIR, f"{role_id}.md")
        if not os.path.exists(path):
            raise FileNotFoundError(f"Role file not found: {path}")
        meta, body = parse_role_file(path)
        validate_meta(meta, path)
        roles.append((meta, body))
    return roles


def render_harness(harness_id, harness_cfg, roles):
    """Render all files for one harness. Returns dict of {rel_path: content}."""
    files = {}
    roster = harness_cfg["roster"]
    shape = roster["shape"]

    agent_dir = roster["dir"]  # e.g. ".claude/agents" or "agents"

    if shape == "md-frontmatter":
        for meta, body in roles:
            rel = os.path.join(agent_dir, f"{meta['id']}.md")
            files[rel] = render_agent_file(meta, body, harness_cfg)
    elif shape == "toml":
        for meta, body in roles:
            rel = os.path.join(agent_dir, f"{meta['id']}.toml")
            files[rel] = render_agent_file_toml(meta, body, harness_cfg)
    else:
        raise NotImplementedError(f"roster shape '{shape}' not implemented")

    # Manual
    files[harness_cfg["instruction_file"]] = render_manual(harness_cfg)

    return files


def write_files(harness_id, rendered):
    """Write rendered files to dist/<harness_id>/."""
    base = os.path.join(DIST_DIR, harness_id)
    base_abs = os.path.realpath(base)
    for rel, content in rendered.items():
        dest = os.path.join(base, rel)
        # Defense-in-depth: never write outside dist/<harness>/ even if a harness
        # config supplied an absolute path or '..' in dir/id/instruction_file.
        if os.path.commonpath([base_abs, os.path.realpath(dest)]) != base_abs:
            raise ValueError(f"refusing to write outside dist/{harness_id}/: {rel!r}")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(content)
    print(f"[generate] {harness_id}: wrote {len(rendered)} files to dist/{harness_id}/")


def check_harness(harness_id, rendered):
    """Diff rendered output vs committed dist files. Return list of drift messages."""
    base = os.path.join(DIST_DIR, harness_id)
    drifts = []
    for rel, content in rendered.items():
        dest = os.path.join(base, rel)
        if not os.path.exists(dest):
            drifts.append(f"MISSING: dist/{harness_id}/{rel}")
            continue
        with open(dest, "r", encoding="utf-8") as fh:
            on_disk = fh.read()
        if on_disk != content:
            diff = "".join(
                difflib.unified_diff(
                    on_disk.splitlines(keepends=True),
                    content.splitlines(keepends=True),
                    fromfile=f"dist/{harness_id}/{rel}",
                    tofile=f"<generated>",
                    n=3,
                )
            )
            drifts.append(f"DRIFT: dist/{harness_id}/{rel}\n{diff}")
    return drifts


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def usage():
    print("Usage: python3 generate.py [--harness <id>] [--check]")
    print("  (no args)           render all harnesses to dist/")
    print("  --harness <id>      render one harness")
    print("  --check             diff generated output vs dist/, exit 1 on drift")


def main(argv):
    args = argv[1:]
    harness_filter = None
    check_mode = False

    i = 0
    while i < len(args):
        if args[i] == "--harness" and i + 1 < len(args):
            harness_filter = args[i + 1]
            i += 2
        elif args[i] == "--check":
            check_mode = True
            i += 1
        elif args[i] in ("-h", "--help"):
            usage()
            return 0
        else:
            print(f"Unknown argument: {args[i]}", file=sys.stderr)
            usage()
            return 1

    # Load config
    with open(HARNESSES_JSON, "r", encoding="utf-8") as fh:
        config = json.load(fh)

    harnesses = config["harnesses"]
    if harness_filter:
        if harness_filter not in harnesses:
            print(f"Error: unknown harness '{harness_filter}'. Known: {list(harnesses)}", file=sys.stderr)
            return 1
        harnesses = {harness_filter: harnesses[harness_filter]}

    roles = load_roles()

    if check_mode:
        all_drifts = []
        for hid, hcfg in harnesses.items():
            rendered = render_harness(hid, hcfg, roles)
            drifts = check_harness(hid, rendered)
            all_drifts.extend(drifts)
        if all_drifts:
            for d in all_drifts:
                print(d, file=sys.stderr)
            print(f"[check] FAIL: {len(all_drifts)} drift(s) found", file=sys.stderr)
            return 1
        print("[check] OK: dist/ matches generated output")
        return 0

    for hid, hcfg in harnesses.items():
        rendered = render_harness(hid, hcfg, roles)
        write_files(hid, rendered)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
