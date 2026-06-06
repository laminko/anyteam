#!/usr/bin/env bash
# install.sh — portable hub-and-spoke team installer
# Requires: bash 3.2+  (NO associative arrays, NO ${var^^}, NO mapfile/readarray)
# Usage: bash install.sh [--harness <id>] [--all] [--dir <project>] [--dry-run] [--force] [-h|--help]
# In a terminal you'll be prompted to pick harness(es) + target dir (flags pre-fill the defaults).
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

Interactive prompts:
  When run in a terminal, you are prompted to select harness(es)
  (space-separated numbers/names, or 'all'; default: claude-code) and to
  confirm the target project directory. Any flags you pass pre-fill these
  prompts, so pressing Enter accepts them. Piped/non-interactive runs skip
  the prompts and fall back to flags + auto-detection.

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

# Disable pathname expansion while resolving harness/dir input below: typed
# tokens (and flag values) are word-split but must never glob against the CWD.
# Re-enabled (set +f) right before the install loop, which DOES rely on globbing.
set -f

# ---------------------------------------------------------------------------
# Interactive selection (TTY only)
# When attached to a terminal, confirm the harness selection and target
# directory. Flags (or claude-code) seed the defaults, so pressing Enter
# accepts them. Piped/CI runs (no TTY) skip this and use flags + auto-detect.
# ---------------------------------------------------------------------------
if [ -t 0 ]; then
    # --- Harness selection (multi-select: numbers, names, or 'all') ---
    if [ "$REQUESTED_HARNESSES" = "ALL" ]; then
        _default_harnesses="$SUPPORTED_HARNESSES"
    elif [ -n "$REQUESTED_HARNESSES" ]; then
        _default_harnesses="$REQUESTED_HARNESSES"
    else
        _default_harnesses="claude-code"
    fi

    echo "Available harnesses:"
    _i=0
    for _s in $SUPPORTED_HARNESSES; do
        _i=$((_i + 1))
        echo "  ${_i}) ${_s}"
    done
    printf "Select harness(es) to install — space-separated numbers/names, or 'all' [%s]: " "$_default_harnesses"
    read -r _reply || _reply=""
    if [ -z "$_reply" ]; then
        _reply="$_default_harnesses"
    fi

    # Resolve the reply into a space-separated list of harness names.
    _reply="$(echo "$_reply" | tr ',' ' ')"
    _selection=""
    for _tok in $_reply; do
        case "$_tok" in
            all|ALL|All)
                _selection="$SUPPORTED_HARNESSES"
                break
                ;;
            *)
                if echo "$_tok" | grep -q '^[0-9][0-9]*$'; then
                    # numeric choice — map position to a harness name
                    _j=0
                    _match=""
                    for _s in $SUPPORTED_HARNESSES; do
                        _j=$((_j + 1))
                        if [ "$_j" = "$_tok" ]; then
                            _match="$_s"
                            break
                        fi
                    done
                    if [ -n "$_match" ]; then
                        _selection="${_selection} ${_match}"
                    else
                        echo "  (ignoring out-of-range choice: ${_tok})" >&2
                    fi
                else
                    # treat as a name; the validation step below rejects unknowns
                    _selection="${_selection} ${_tok}"
                fi
                ;;
        esac
    done
    _selection="${_selection# }"   # trim leading space
    if [ -n "$_selection" ]; then
        REQUESTED_HARNESSES="$_selection"
    else
        REQUESTED_HARNESSES="$_default_harnesses"
    fi

    # --- Target project directory ---
    printf "Project directory to set up the team in [%s]: " "$TARGET_DIR"
    read -r _reply || _reply=""
    case "$_reply" in
        "~")   _reply="$HOME" ;;
        "~/"*) _reply="${HOME}/${_reply#"~/"}" ;;
    esac
    if [ -n "$_reply" ]; then
        TARGET_DIR="$_reply"
    fi
    if [ ! -d "$TARGET_DIR" ]; then
        echo "  (note: '${TARGET_DIR}' does not exist yet — it will be created)"
    fi
    echo ""
fi

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

    # Never write THROUGH a symlink at the destination (symlink-redirect attack:
    # a pre-planted dest symlink — even a dangling one — would make cp follow it
    # and write outside the intended tree).
    if [ -L "$_cdest" ]; then
        echo "refused (symlink dest, not following): ${_crel}" >&2
        return
    fi

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
        mkdir -p -- "$(dirname -- "$_cdest")"
        cp -- "$_csrc" "$_cdest"
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
        _rel="${_abs:${#_src}+1}"
        _dest="${TARGET_DIR}/${_rel}"

        # Never write THROUGH a symlink at the destination (symlink-redirect attack).
        if [ -L "$_dest" ]; then
            echo "refused (symlink dest, not following): ${_rel}" >&2
            continue
        fi

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
            mkdir -p -- "$(dirname -- "$_dest")"
            cp -- "$_abs" "$_dest"
            echo "added         : ${_rel}"
            _added=$((_added + 1))
        fi
    done < <(find "$_src" -type f | sort)

    if [ "$DRY_RUN" = "0" ]; then
        echo ""
        if [ "$_harness" = "pi" ]; then
            _pi_pkg="npm:@tintinweb/pi-subagents@0.10.0"
            echo "Pi subagents need a separate, THIRD-PARTY community extension to work:"
            echo "  @tintinweb/pi-subagents (MIT, maintained outside anyteam)."
            _ans="n"
            if [ -t 0 ]; then
                printf "  Install it now via 'pi install %s'? [y/N] " "$_pi_pkg"
                read -r _ans || _ans="n"
            fi
            case "$_ans" in
                y|Y|yes|YES)
                    if command -v pi >/dev/null 2>&1; then
                        echo "  Running: pi install ${_pi_pkg}"
                        pi install "${_pi_pkg}" || echo "  pi install failed — run it manually when ready."
                    else
                        echo "  'pi' is not on PATH. Once Pi is installed, run:  pi install ${_pi_pkg}"
                    fi
                    ;;
                *)
                    echo "  Skipped (opt-in). To enable Pi subagents later, run:"
                    echo "    pi install ${_pi_pkg}"
                    ;;
            esac
        fi
        echo "[${_harness}] done — added: ${_added}, skipped: ${_skipped}"
    fi
}

# ---------------------------------------------------------------------------
# Run installs
# ---------------------------------------------------------------------------
set +f   # restore globbing — install_harness relies on "${_src}"/*.md expansion
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
