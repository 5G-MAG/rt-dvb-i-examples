#!/usr/bin/env python3
"""Check that every specification citation in these repositories resolves.

Two documents are in play and both number clauses in the same ranges: A184r2 clause 4.8 is
"Region targeting", while the specification has no such clause and puts HTTP requests elsewhere. A
citation written as a bare "clause 4.8" is therefore resolved by a reader against whichever
document they assume. That is not hypothetical: it is how comments came to cite implementation
guidance for behaviour the specification governs, and how three citations came to name clauses
covering something else entirely. Both classes are caught here.

A citation must name its document, and the clause must exist in that document. In prose files an
unlabelled citation is reported but not failed, because prose legitimately discusses a clause the
surrounding sentence has already attributed.

Bring your own documents. The specification text is not carried in any of these repositories, and
must not be. Point DVBI_SPECS at a directory holding plain-text extractions, outside every working
tree:

    DVBI_SPECS=~/.local/share/dvb-i-specs tools/verify-citations.py

    ts_103770.txt   ETSI TS 103 770, the specification
    A184r2.txt      DVB Document A184r2, the implementation guidelines
    tr_103972.txt   ETSI TR 103 972, DVB-I over 5G deployment guidelines
    ts_126512.txt   ETSI TS 126 512, 5G Media Streaming protocols
    ts_126510.txt   ETSI TS 126 510, Media delivery
    ts_103720.txt   ETSI TS 103 720, the 5G Broadcast system
    ts_129116.txt   ETSI TS 129 116, the xMB reference point

Produce them with `pdftotext -layout`. Without them the check skips and exits 0.

What this does NOT check: whether the clause says what the comment claims. A citation can resolve
to a real clause that is about something else, which is exactly what happened twice. Only reading
catches that.

Exit code 0 = every citation resolves (or skipped), 1 = at least one does not.
"""
import os
import re
import sys
from pathlib import Path

SPECS = Path(os.path.expanduser(os.environ.get("DVBI_SPECS", "~/.local/share/dvb-i-specs")))
REPOS_ROOT = Path(__file__).resolve().parents[2]

DOCUMENTS = {
    "TS 103 770": "ts_103770.txt",
    "A184r2": "A184r2.txt",
    "TR 103 972": "tr_103972.txt",
    "TS 126 512": "ts_126512.txt",
    "TS 126 510": "ts_126510.txt",
    "TS 103 720": "ts_103720.txt",
    "TS 129 116": "ts_129116.txt",
}
# How each document may be named in a citation, longest first so the specific wins.
LABELS = [
    ("A184r2", "A184r2"),
    ("TS 103 770", "TS 103 770"),
    ("ETSI TS 103 770", "TS 103 770"),
    ("TR 103 972", "TR 103 972"),
    ("ETSI TR 103 972", "TR 103 972"),
    ("TS 126 512", "TS 126 512"),
    ("TS 126 510", "TS 126 510"),
    ("TS 103 720", "TS 103 720"),
    ("TS 129 116", "TS 129 116"),
]
SCAN = (".js", ".md", ".py")
SKIP_DIRS = {"node_modules", ".git", "run", "schemas", "config-history"}
# Documents cited here that this tool holds no copy of, so cannot resolve. Naming them keeps them
# visible rather than silently passing.
FOREIGN = ("ISO/IEC 23009-1", "TS 102 822", "TS 102 822-3-1", "RFC",
           "TS 126 501", "TS 126 346", "TS 126 347")

# "section" is deliberately not matched: in these repositories it refers to a heading of the
# document doing the writing, not to a clause of a specification.
CITATION = re.compile(r"(?:clause|§)\s*([A-Z]?[0-9]+(?:\.[0-9]+)*)", re.IGNORECASE)


def clause_titles(path):
    """clause number -> title, from headings and the table of contents."""
    out = {}
    for line in path.read_text(errors="ignore").split("\n"):
        m = re.match(r"^\s*((?:[A-Z]\.)?[0-9]+(?:\.[0-9]+)*)\s{2,}(.+?)(?:\s*\.{3,}.*)?$", line.rstrip())
        if not m:
            continue
        num, title = m.group(1), re.sub(r"\s*\.{2,}\s*[0-9]*$", "", m.group(2)).strip()
        if not title or len(title) > 80 or title[0].islower():
            continue
        out.setdefault(num, title)
    return out


def document_for(line, previous):
    """Which document a citation names, looking at the line and then the one above it, because a
    comment often carries the document name on its first line and the clause on its second."""
    for text in (line, previous):
        best = None
        for label, doc in LABELS:
            if label in text:
                if best is None or len(label) > len(best[0]):
                    best = (label, doc)
        if best:
            return best[1]
    return None


def main():
    missing = [f for f in DOCUMENTS.values() if not (SPECS / f).is_file()]
    if missing:
        print(f"Citation check: SKIPPED (no document text at {SPECS}).")
        print(f"Missing: {', '.join(missing)}. See the header of this file; the text is not")
        print("carried in these repositories and must be supplied from outside the working tree.")
        return 0

    titles = {doc: clause_titles(SPECS / f) for doc, f in DOCUMENTS.items()}
    print(f"Documents: {SPECS}")
    for doc, t in titles.items():
        print(f"  {doc}: {len(t)} clauses indexed")
    print()

    failures, unlabelled, checked = [], [], 0
    for path in sorted(REPOS_ROOT.rglob("*")):
        if path.suffix not in SCAN or not path.is_file():
            continue
        if SKIP_DIRS & set(path.parts):
            continue
        lines = path.read_text(errors="ignore").split("\n")
        for i, line in enumerate(lines):
            for m in CITATION.finditer(line):
                before = line[: m.start()]
                if any(f in before[-40:] or f in line for f in FOREIGN):
                    continue
                num = m.group(1)
                doc = document_for(before, lines[i - 1] if i else "")
                where = f"{path.relative_to(REPOS_ROOT)}:{i + 1}"
                if doc is None:
                    unlabelled.append((where, num, line.strip()[:90], path.suffix))
                    continue
                checked += 1
                if num not in titles[doc]:
                    failures.append((where, doc, num, line.strip()[:90]))

    hard_unlabelled = [u for u in unlabelled if u[3] == ".js"]
    for where, doc, num, text in failures:
        print(f"MISSING  {where}: {doc} clause {num} does not exist in that document")
        print(f"         {text}")
    for where, num, text, _ in hard_unlabelled:
        print(f"UNNAMED  {where}: clause {num} names no document, and code must say which")
        print(f"         {text}")
    soft = [u for u in unlabelled if u[3] != ".js"]
    if soft:
        print(f"\n{len(soft)} unlabelled citation(s) in prose, not failed:")
        for where, num, text, _ in soft:
            print(f"  {where}: clause {num}")

    bad = len(failures) + len(hard_unlabelled)
    print(f"\n==== {checked} citation(s) checked, "
          f"{'all resolve' if bad == 0 else f'{bad} problem(s)'} ====")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
