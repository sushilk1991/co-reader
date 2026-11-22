#!/bin/sh
# Links the Coreader agent skill into every agent that is set up on this machine:
#   ~/.claude/skills/coreader   Claude Code
#   ~/.codex/skills/coreader    Codex
#   ~/.agents/skills/coreader   Antigravity and other tools that read ~/.agents
#
# An agent is "set up" when its folder (~/.claude, ~/.codex, ~/.agents) exists; nothing
# is created for agents that are not installed. Safe to run again: an existing link is
# repointed, and a real folder someone put there is left alone.
set -eu

source_dir="$(cd "$(dirname "$0")" && pwd -P)/coreader"
if [ ! -f "$source_dir/SKILL.md" ]; then
    echo "install.sh: $source_dir/SKILL.md is missing" >&2
    exit 1
fi

status=0
found=0
for agent_dir in "$HOME/.claude" "$HOME/.codex" "$HOME/.agents"; do
    [ -d "$agent_dir" ] || continue
    found=1
    target="$agent_dir/skills/coreader"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        echo "skipped  $target (exists and is not a link; remove it to install)" >&2
        status=1
        continue
    fi
    mkdir -p "$agent_dir/skills"
    # -n: replace a link to a directory instead of creating a link inside it.
    ln -sfn "$source_dir" "$target"
    echo "linked   $target -> $source_dir"
done

if [ "$found" -eq 0 ]; then
    echo "No agent folders found (~/.claude, ~/.codex, ~/.agents); nothing to do."
fi
exit "$status"
