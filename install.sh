#!/usr/bin/env bash
# install.sh — portable hub-and-spoke team installer
# Requires: bash 3.2+  (NO associative arrays, NO ${var^^}, NO mapfile/readarray)
# Usage: bash install.sh [--harness <id>] [--all] [--dir <project>] [--dry-run] [--force] [-h|--help]
#
# Detection markers (when no --harness/--all given):
#   claude-code  : .claude/ directory OR CLAUDE.md
#   opencode     : .opencode/
#   gemini       : .gemini/ OR GEMINI.md
#   codex        : ~/.codex/  (user-level)
#   pi           : .pi/

set -euo pipefail

# ---------------------------------------------------------------------------
# Locate the repo/dist directory relative to this script
# ---------------------------------------------------------------------------
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="${SKILL_DIR}/dist"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
TARGET_DIR="${PWD}"
DRY_RUN=0
FORCE=0
REQUESTED_HARNESSES=""   # space-separated list, or "ALL"

# ---------------------------------------------------------------------------
# Supported harnesses (space-separated, bash-3.2-clean list)
# ---------------------------------------------------------------------------
SUPPORTED_HARNESSES="claude-code opencode gemini codex pi"

usage() {
    cat <<'USAGE'
Usage: bash install.sh [OPTIONS]

Install the hub-and-spoke specialist team into a project.

Options:
  --harness <id>   Install a specific harness (repeatable, or comma-separated).
                   Supported: claude-code opencode gemini codex pi
  --all            Install all supported harnesses.
  --dir <path>     Target project directory (default: current directory).
  --dry-run        Print planned actions without copying any files.
  --force          Overwrite existing files (default: skip existing).
  -h, --help       Show this help.

Auto-detection (when no --harness/--all given):
  claude-code  : target dir contains .claude/ or CLAUDE.md
  opencode     : target dir contains .opencode/
  gemini       : target dir contains .gemini/ or GEMINI.md
  codex        : ~/.codex/ directory exists (user-level)
  pi           : target dir contains .pi/

Supported harnesses: claude-code opencode gemini codex pi
USAGE
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --harness)
            if [ $# -lt 2 ]; then
                echo "Error: --harness requires an argument" >&2
                exit 1
            fi
            # Accept comma-separated: --harness claude-code,opencode
            _arg="$2"
            _arg_space="$(echo "$_arg" | tr ',' ' ')"
            if [ -z "$REQUESTED_HARNESSES" ]; then
                REQUESTED_HARNESSES="$_arg_space"
            else
                REQUESTED_HARNESSES="${REQUESTED_HARNESSES} ${_arg_space}"
            fi
            shift 2
            ;;
        --all)
            REQUESTED_HARNESSES="ALL"
            shift
            ;;
        --dir)
            if [ $# -lt 2 ]; then
                echo "Error: --dir requires an argument" >&2
                exit 1
            fi
            TARGET_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown argument '$1'" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Resolve harnesses to install
# ---------------------------------------------------------------------------

# If ALL, expand to full list
if [ "$REQUESTED_HARNESSES" = "ALL" ]; then
    REQUESTED_HARNESSES="$SUPPORTED_HARNESSES"
fi

# Auto-detect if nothing specified
if [ -z "$REQUESTED_HARNESSES" ]; then
    DETECTED=""
    # claude-code: .claude/ dir or CLAUDE.md present
    if [ -d "${TARGET_DIR}/.claude" ] || [ -f "${TARGET_DIR}/CLAUDE.md" ]; then
        DETECTED="${DETECTED} claude-code"
    fi
    # opencode: .opencode/ dir present
    if [ -d "${TARGET_DIR}/.opencode" ]; then
        DETECTED="${DETECTED} opencode"
    fi
    # gemini: .gemini/ dir or GEMINI.md present
    if [ -d "${TARGET_DIR}/.gemini" ] || [ -f "${TARGET_DIR}/GEMINI.md" ]; then
        DETECTED="${DETECTED} gemini"
    fi
    # codex: user-level ~/.codex dir exists
    _codex_home="${CODEX_HOME:-${HOME}/.codex}"
    if [ -d "$_codex_home" ]; then
        DETECTED="${DETECTED} codex"
    fi
    # pi: .pi/ dir present
    if [ -d "${TARGET_DIR}/.pi" ]; then
        DETECTED="${DETECTED} pi"
    fi
    DETECTED="${DETECTED# }"  # trim leading space

    if [ -z "$DETECTED" ]; then
        echo "Error: could not detect a supported harness in '${TARGET_DIR}'." >&2
        echo "Supported harnesses: ${SUPPORTED_HARNESSES}" >&2
        echo "" >&2
        usage >&2
        exit 1
    fi
    REQUESTED_HARNESSES="$DETECTED"
    echo "Auto-detected harness(es): ${DETECTED}"
fi

# ---------------------------------------------------------------------------
# Validate requested harnesses
# ---------------------------------------------------------------------------
for _h in $REQUESTED_HARNESSES; do
    _found=0
    for _s in $SUPPORTED_HARNESSES; do
        if [ "$_h" = "$_s" ]; then
            _found=1
            break
        fi
    done
    if [ "$_found" = "0" ]; then
        echo "Error: harness '$_h' is not supported. Supported: ${SUPPORTED_HARNESSES}" >&2
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# Install each harness
# ---------------------------------------------------------------------------

# Helper: copy one file (honoring DRY_RUN, FORCE, no-clobber)
# Usage: _copy_one _abs_src _abs_dest _display_rel
# Increments global _added/_skipped counters.
_copy_one() {
    _csrc="$1"
    _cdest="$2"
    _crel="$3"

    if [ "$DRY_RUN" = "1" ]; then
        if [ -e "$_cdest" ]; then
            echo "dry-run skip (exists): ${_crel}"
        else
            echo "dry-run add          : ${_crel}"
        fi
        return
    fi

    if [ -e "$_cdest" ] && [ "$FORCE" = "0" ]; then
        echo "skip  (exists): ${_crel}"
        _skipped=$((_skipped + 1))
    else
        mkdir -p "$(dirname "$_cdest")"
        cp "$_csrc" "$_cdest"
        echo "added         : ${_crel}"
        _added=$((_added + 1))
    fi
}

install_harness() {
    _harness="$1"
    _src="${DIST_DIR}/${_harness}"

    if [ ! -d "$_src" ]; then
        echo "Error: dist directory not found: ${_src}" >&2
        echo "Run 'python3 generate.py' first to build the dist assets." >&2
        return 1
    fi

    _added=0
    _skipped=0

    # -----------------------------------------------------------------------
    # Codex: user-scope install — agents go to ~/.codex/agents/, manual to $TARGET_DIR
    # -----------------------------------------------------------------------
    if [ "$_harness" = "codex" ]; then
        _codex_home="${CODEX_HOME:-${HOME}/.codex}"
        _codex_agents_dst="${_codex_home}/agents"
        _codex_agents_src="${_src}/agents"

        # Install each .toml agent file to the user-global agents dir
        while IFS= read -r _abs; do
            _fname="$(basename "$_abs")"
            _copy_one "$_abs" "${_codex_agents_dst}/${_fname}" "agents/${_fname} -> ${_codex_agents_dst}/${_fname}"
        done < <(find "$_codex_agents_src" -name "*.toml" -type f | sort)

        # Install AGENTS.md to TARGET_DIR
        _manual_src="${_src}/AGENTS.md"
        if [ -f "$_manual_src" ]; then
            _copy_one "$_manual_src" "${TARGET_DIR}/AGENTS.md" "AGENTS.md"
        fi

        if [ "$DRY_RUN" = "0" ]; then
            echo ""
            echo "Note: Codex roster installed user-globally (${_codex_agents_dst}) — shared across all projects by design."
            echo "[${_harness}] done — added: ${_added}, skipped: ${_skipped}"
        fi
        return
    fi

    # -----------------------------------------------------------------------
    # Generic walk for all other harnesses (md-frontmatter, project-scope)
    # -----------------------------------------------------------------------

    # Identify the instruction file (the top-level .md manual in the dist root)
    _instruction_file=""
    for _f in "${_src}"/*.md; do
        if [ -f "$_f" ]; then
            _instruction_file="$(basename "$_f")"
            break
        fi
    done

    while IFS= read -r _abs; do
        _rel="${_abs#${_src}/}"
        _dest="${TARGET_DIR}/${_rel}"

        if [ "$DRY_RUN" = "1" ]; then
            if [ -e "$_dest" ]; then
                echo "dry-run skip (exists): ${_rel}"
            else
                echo "dry-run add          : ${_rel}"
            fi
            continue
        fi

        if [ -e "$_dest" ] && [ "$FORCE" = "0" ]; then
            echo "skip  (exists): ${_rel}"
            if [ "$(basename "$_rel")" = "$_instruction_file" ]; then
                echo "  hint: to update the manual, merge by hand from: dist/${_harness}/${_rel}"
            fi
            _skipped=$((_skipped + 1))
        else
            mkdir -p "$(dirname "$_dest")"
            cp "$_abs" "$_dest"
            echo "added         : ${_rel}"
            _added=$((_added + 1))
        fi
    done < <(find "$_src" -type f | sort)

    if [ "$DRY_RUN" = "0" ]; then
        echo ""
        if [ "$_harness" = "pi" ]; then
            echo "Note: Pi subagents require the extension — run:  pi install npm:@tintinweb/pi-subagents"
        fi
        echo "[${_harness}] done — added: ${_added}, skipped: ${_skipped}"
    fi
}

# ---------------------------------------------------------------------------
# Run installs
# ---------------------------------------------------------------------------
for _harness in $REQUESTED_HARNESSES; do
    echo ""
    echo "=== Installing harness: ${_harness} ==="
    install_harness "$_harness"
done

# ---------------------------------------------------------------------------
# Post-install message
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" = "0" ]; then
    echo ""
    echo "NEXT: run the codebase intake (see INTAKE.md) and fill the Project brief in your manual."
fi
