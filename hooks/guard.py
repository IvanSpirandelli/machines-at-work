#!/usr/bin/env python3
"""PreToolUse guard: deterministic safety rails.
Blocks: force-push, push to main/master, destructive rm, and any edit to the
scaffold plugin itself (self-modification must go through /scaffold:retro proposals).
Exit 2 = block (stderr goes to the agent). Exit 0 = allow.
"""
import json
import os
import re
import sys

BASH_DENY = [
    (r"git\s+push\b.*(\s--force\b|\s-f\b|\+\S+:)", "force-push is forbidden"),
    (r"git\s+push\b.*\b(main|master)\b", "pushing to the default branch is forbidden; work on the task branch, task.sh merges"),
    (r"rm\s+(-\w*[rf]\w*\s+)+(/|~|\$HOME)(\s|$)", "destructive rm on / or ~ is forbidden"),
    (r"git\s+checkout\s+.*--\s+\.", "wholesale checkout-discard is forbidden; revert specific files"),
]

def deny(reason: str) -> None:
    print(f"BLOCKED by scaffold guard: {reason}", file=sys.stderr)
    sys.exit(2)

def main() -> None:
    data = json.load(sys.stdin)
    tool = data.get("tool_name", "")
    tin = data.get("tool_input", {})

    if tool == "Bash":
        cmd = tin.get("command", "")
        for pattern, reason in BASH_DENY:
            if re.search(pattern, cmd):
                deny(reason)

    if tool in ("Write", "Edit", "NotebookEdit"):
        plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT", "")
        path = os.path.realpath(tin.get("file_path", ""))
        if plugin_root and path.startswith(os.path.realpath(plugin_root) + os.sep):
            deny("the scaffold plugin is read-only inside projects; use /scaffold:retro to propose changes")

    sys.exit(0)

if __name__ == "__main__":
    main()
