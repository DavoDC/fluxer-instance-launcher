"""No tracked file may hold an absolute drive-letter Users-folder path: such a path names one machine, breaks on any other, and
leaks a username into a repo that may one day be shared. Write repo-relative paths, or `<Sibling repo>/path` for a
neighbouring repo. docs/HISTORY.md is exempt (an immutable dated record). Silent when green, file:line on failure."""
import re
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
EXEMPT = {"docs/HISTORY.md", "tests/test_no_absolute_user_paths.py"}
ABSOLUTE = re.compile(r"[A-Za-z]:[\/]+Users[\/]")


def test_no_absolute_user_paths_in_tracked_files():
    files = subprocess.run(["git", "ls-files"], cwd=REPO, capture_output=True, text=True).stdout.split("\n")
    hits = []
    for rel in files:
        path = REPO / rel
        if not rel or rel in EXEMPT or not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue  # binary
        hits += [f"{rel}:{n}" for n, line in enumerate(text.splitlines(), 1) if ABSOLUTE.search(line)]
    assert not hits, "absolute user-folder paths (make them repo-relative):\n" + "\n".join(hits)
