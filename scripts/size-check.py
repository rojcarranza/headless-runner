#!/usr/bin/env python3
"""size-check.py - fail when a code file is over 1,000 lines and not listed in
.baseline-long-files. A listed file may shrink but never grow.
  ./scripts/size-check.py [DIR]    check DIR, the top of a git working copy
                                   (default: the repository)
Exit codes: 0 ok, 1 a new or grown file over the limit, 2 a usage error.

This is a standard-library copy of the baseline program's size command, so the
gate needs no program installed. Keep its code-file rules, list format and
messages the same as baseline's, so both read and write one list.
"""
import subprocess
import sys
from pathlib import Path

LIMIT = 1000
LIST_FILE = ".baseline-long-files"
CODE_EXTENSIONS = {
    ".swift", ".go", ".py", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".sh", ".bash", ".nix",
    ".rs", ".kt", ".java", ".c", ".h", ".cc", ".cpp", ".m", ".rb",
}
# Dependency, build and bundle output never counts as project-written code.
SKIPPED_PARTS = {"node_modules", "vendor", "dist", "build", "Pods", ".build", "DerivedData", "third_party"}
SKIPPED_SUFFIXES = (".min.js", ".bundle.js", ".pb.go", ".generated.swift")


class UsageError(Exception):
    """A clear error, reported with exit code 2."""


def git(root, *args):
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)


def project_root(path):
    root = Path(path).resolve()
    if not root.is_dir():
        raise UsageError("not a folder: %s" % path)
    top = git(root, "rev-parse", "--show-toplevel")
    if top.returncode != 0 or Path(top.stdout.strip()).resolve() != root:
        raise UsageError("not the top of a git working copy: %s" % root)
    return root


def files(root):
    """Tracked files plus untracked files that are not ignored."""
    out = git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
    if out.returncode != 0:
        raise UsageError("git ls-files failed: %s" % out.stderr.strip())
    names = sorted(set(n for n in out.stdout.split("\0") if n))
    return [n for n in names if (root / n).is_file()]


def is_code(rel):
    parts = Path(rel).parts
    if any(p in SKIPPED_PARTS for p in parts) or rel.endswith(SKIPPED_SUFFIXES):
        return False
    return Path(rel).suffix in CODE_EXTENSIONS


def line_count(path):
    with open(path, "rb") as handle:
        return sum(1 for _ in handle)


def read_list(root):
    listed = {}
    path = root / LIST_FILE
    text = path.read_text(errors="replace") if path.is_file() else ""
    for line in text.splitlines():
        if line.strip() and not line.startswith("#"):
            rel, _, count = line.rpartition("\t")
            if rel and count.strip().isdigit():
                listed[rel] = int(count)
    return listed


def measure(root):
    """Return (over, problems, notes): files over the limit, failures and shrink notes."""
    listed = read_list(root)
    over = {}
    for rel in files(root):
        if is_code(rel):
            count = line_count(root / rel)
            if count > LIMIT:
                over[rel] = count
    problems, notes = [], []
    for rel, count in sorted(over.items()):
        if rel not in listed:
            problems.append("%s has %d lines and is not on the list" % (rel, count))
        elif count > listed[rel]:
            problems.append("%s grew from %d to %d lines" % (rel, listed[rel], count))
        elif count < listed[rel]:
            notes.append("%s shrank from %d to %d lines; update the list" % (rel, listed[rel], count))
    for rel in sorted(listed):
        if rel not in over:
            notes.append("%s is under the limit or gone; remove it from the list" % rel)
    return over, problems, notes


def main(argv):
    if len(argv) > 1:
        print("usage: size-check.py [DIR]")
        return 2
    try:
        root = project_root(argv[0] if argv else Path(__file__).resolve().parent.parent)
        over, problems, notes = measure(root)
    except (UsageError, OSError) as error:
        print("error: %s" % error)
        return 2
    for line in problems:
        print("fail: " + line)
    for line in notes:
        print("note: " + line)
    print("size: %d files over %d lines, %d problems" % (len(over), LIMIT, len(problems)))
    if problems:
        print("next: split the file; listed files may shrink but never grow")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
