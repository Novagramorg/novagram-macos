#!/usr/bin/env python3
"""Accessibility lint: every control and image created in the macOS code needs a label or a decorative mark.

Usage:
  a11y_lint.py [--repo ROOT] [--package NAME] [--summary] [--json OUT]

A creation site is `ImageButton(`, `TextButton(`, `TitleButton(`, `Control(` or `ImageView(` assigned to a name.
It passes when the same file gives that name one of:
  .setAccessibilityLabel(   .appTooltip =   .toolTip =   .isAccessibilityDecorative =
  .set(text:   (text buttons, whose title is their label)
"""

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
SCAN_DIRS = ["packages", "Telegram-Mac", "TelegramShare"]
SKIP_DIRS = {".build", ".swiftpm", "Tests"}
SKIP_FILE = re.compile(r"(Lab|LabSession|PerfLab)[A-Za-z]*\.swift$")

KINDS = ["ImageButton", "TextButton", "TitleButton", "Control", "ImageView"]
CREATION = re.compile(
    r"(?:(?:let|var)\s+|\bself\.|^\s*)([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*[A-Za-z_.<>?!]+\s*)?=\s*(" + "|".join(KINDS) + r")\s*\(",
    re.M,
)
CLOSURE_CREATION = re.compile(
    r"(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(" + "|".join(KINDS) + r")\s*=\s*\{",
)


def labelled(text, name, kind):
    patterns = [
        rf"\b{name}\??\.setAccessibilityLabel\(",
        rf"\b{name}\??\.appTooltip\s*=",
        rf"\b{name}\??\.toolTip\s*=",
        rf"\b{name}\??\.isAccessibilityDecorative\s*=",
    ]
    if kind in ("TextButton", "TitleButton"):
        patterns.append(rf"\b{name}\??\.set\(text:")
    return any(re.search(p, text) for p in patterns)


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return re.sub(r"(?<!:)//[^\n]*", "", text)


def module_of(rel):
    parts = rel.split(os.sep)
    return parts[1] if parts[0] == "packages" and len(parts) > 1 else parts[0]


ROW_BASES = {"TableRowItem"}
ROW_DECL = re.compile(r"\bclass\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^{]*?>)?\s*:\s*([A-Za-z_][A-Za-z0-9_.]*)")
ROW_OVERRIDE = re.compile(r"override\s+var\s+(accessibilityLabel|accessibilityIsSpacer)\b")


def row_findings(repo, sources, package):
    classes = {}
    for rel, module, text in sources:
        for m in ROW_DECL.finditer(text):
            name, base = m.group(1), m.group(2).split(".")[-1]
            start = text.find("{", m.end())
            depth, end = 0, len(text)
            for i in range(start, len(text)):
                if text[i] == "{":
                    depth += 1
                elif text[i] == "}":
                    depth -= 1
                    if depth == 0:
                        end = i
                        break
            body = text[start:end]
            own = False
            for o in ROW_OVERRIDE.finditer(body):
                own = "exact" if re.match(r"[^{]*\{[^}]*type\(of:\s*self\)\s*==", body[o.end():o.end() + 300], re.S) and own is not True else True
            classes.setdefault(name, []).append((base, rel, module, text.count("\n", 0, m.start()) + 1, own))
    cache = {}

    def is_row(name, seen=()):
        if name in ROW_BASES:
            return True
        if name in seen or name not in classes:
            return False
        return any(is_row(base, seen + (name,)) for base, *_ in classes[name])

    def labelled(name, seen=()):
        if name in cache:
            return cache[name]
        if name in seen or name not in classes:
            return False
        result = any(own is not False or inherited(base, seen + (name,)) for base, _, _, _, own in classes[name])
        cache[name] = result
        return result

    def inherited(name, seen=()):
        if name in seen or name not in classes:
            return False
        return any(own is True or inherited(base, seen + (name,)) for base, _, _, _, own in classes[name])

    findings = []
    for name, decls in classes.items():
        if name in ROW_BASES or not is_row(name):
            continue
        for base, rel, module, line, own in decls:
            if package and module != package:
                continue
            if module == "TGUIKit":
                continue
            if not labelled(name):
                findings.append({"module": module, "path": rel, "line": line, "kind": "TableRowItem", "name": name})
    return findings


def shared_base_overrides(repo):
    classes = {}
    for top in SCAN_DIRS:
        for root, dirs, files in os.walk(os.path.join(repo, top)):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.endswith("Tests"))
            for name in sorted(files):
                if not name.endswith(".swift") or SKIP_FILE.search(name):
                    continue
                path = os.path.join(root, name)
                rel = os.path.relpath(path, repo)
                with open(path, encoding="utf-8", errors="replace") as f:
                    text = strip_comments(f.read())
                for m in ROW_DECL.finditer(text):
                    start = text.find("{", m.end())
                    depth, end = 0, len(text)
                    for i in range(start, len(text)):
                        if text[i] == "{":
                            depth += 1
                        elif text[i] == "}":
                            depth -= 1
                            if depth == 0:
                                end = i
                                break
                    classes.setdefault(m.group(1), []).append((m.group(2).split(".")[-1], rel, module_of(rel), bool(ROW_OVERRIDE.search(text[start:end]))))
    result = []
    for name, decls in classes.items():
        for _, rel, module, own in decls:
            if not own:
                continue
            outside = sorted({m for sub, sd in classes.items() for base, _, m, _ in sd if base == name and m != module})
            if outside:
                result.append((rel, name, outside))
    return result


def scan(repo, package=None):
    findings = []
    sources = []
    for top in SCAN_DIRS:
        for root, dirs, files in os.walk(os.path.join(repo, top)):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.endswith("Tests"))
            for name in sorted(files):
                if not name.endswith(".swift") or SKIP_FILE.search(name):
                    continue
                path = os.path.join(root, name)
                if os.path.islink(path):
                    continue
                rel = os.path.relpath(path, repo)
                module = module_of(rel)
                if module == "TGUIKit":
                    continue
                with open(path, encoding="utf-8", errors="replace") as f:
                    text = strip_comments(f.read())
                sources.append((rel, module, text))
                if package and module != package:
                    continue
                for pattern in (CREATION, CLOSURE_CREATION):
                    for m in pattern.finditer(text):
                        var, kind = m.group(1), m.group(2)
                        if var in ("let", "var", "self"):
                            continue
                        if labelled(text, var, kind):
                            continue
                        if pattern is CLOSURE_CREATION:
                            body = text[m.end(): m.end() + 1500]
                            inner = re.search(rf"(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*{kind}\s*\(", body)
                            if inner and labelled(body, inner.group(1), kind):
                                continue
                        findings.append({
                            "module": module,
                            "path": rel,
                            "line": text.count("\n", 0, m.start()) + 1,
                            "kind": kind,
                            "name": var,
                        })
    findings.extend(row_findings(repo, sources, package))
    unique = {}
    for f in findings:
        unique[(f["path"], f["line"], f["name"])] = f
    return sorted(unique.values(), key=lambda f: (f["module"], f["path"], f["line"]))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=DEFAULT_REPO)
    parser.add_argument("--package")
    parser.add_argument("--summary", action="store_true")
    parser.add_argument("--json")
    parser.add_argument("--bases", action="store_true")
    args = parser.parse_args()
    if args.bases:
        for rel, name, outside in shared_base_overrides(args.repo):
            print(f"{rel}: '{name}' overrides an accessibility label and is subclassed in {', '.join(outside)}")
        return
    findings = scan(args.repo, args.package)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(findings, f, indent=1)
    if args.summary:
        counts = {}
        for f in findings:
            counts[f["module"]] = counts.get(f["module"], 0) + 1
        for module, count in sorted(counts.items(), key=lambda kv: -kv[1]):
            print(f"{count:5d}  {module}")
    else:
        for f in findings:
            if f["kind"] == "TableRowItem":
                print(f"{f['path']}:{f['line']}: row item '{f['name']}' has no accessibilityLabel override (or accessibilityIsSpacer)")
            else:
                print(f"{f['path']}:{f['line']}: {f['kind']} '{f['name']}' has no accessibility label or decorative mark")
    print(f"a11y lint: {len(findings)} unlabeled creation site(s)")
    sys.exit(1 if findings else 0)


if __name__ == "__main__":
    main()
