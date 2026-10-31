"""Inspect actual package bytes and extract only checked ZIP members.

No builds, package commands, network access, global configuration or cleanup.
The Node orchestrator supplies a git-archive source export and one package ZIP.
"""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import unicodedata
from urllib.parse import unquote
import zipfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def save(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def inspect_zip(archive):
    """Validate the complete namespace before creating or writing any member."""
    records = []
    seen = {}
    spellings = {}
    with zipfile.ZipFile(archive) as package:
        for item in package.infolist():
            name = item.filename
            if not name or "\\" in name or "\x00" in name:
                raise ValueError("invalid ZIP path: " + repr(name))
            relative = name[:-1] if item.is_dir() else name
            parts = relative.split("/")
            if name.startswith("/") or any(
                part in ("", ".", "..") or ":" in part for part in parts
            ):
                raise ValueError("non-relative/non-canonical ZIP path: " + repr(name))
            if PurePosixPath(relative).as_posix() != relative:
                raise ValueError("non-canonical ZIP path: " + repr(name))
            # Reject aliases that collide on Windows or normalization-aware FSs.
            if any(part.endswith((" ", ".")) for part in parts):
                raise ValueError("unsafe platform path: " + repr(name))
            if any(re.fullmatch(r"(?i)(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?", part) for part in parts):
                raise ValueError("reserved platform path: " + repr(name))
            key = unicodedata.normalize("NFC", relative).casefold()
            if key in seen:
                raise ValueError("duplicate/conflicting ZIP member: " + repr(name))
            for depth in range(1, len(parts) + 1):
                spelling = "/".join(parts[:depth])
                normalized = unicodedata.normalize("NFC", spelling).casefold()
                if normalized in spellings and spellings[normalized] != spelling:
                    raise ValueError("platform/normalization path alias: " + repr(name))
                spellings[normalized] = spelling
            kind = stat.S_IFMT(item.external_attr >> 16)
            if kind not in (0, stat.S_IFREG, stat.S_IFDIR):
                raise ValueError("ZIP link or special member rejected: " + repr(name))
            if kind == stat.S_IFDIR and not item.is_dir():
                raise ValueError("inconsistent ZIP directory type: " + repr(name))
            if kind == stat.S_IFREG and item.is_dir():
                raise ValueError("regular ZIP file has directory spelling: " + repr(name))
            if item.flag_bits & 1:
                raise ValueError("encrypted ZIP member rejected: " + repr(name))
            content = package.read(item)  # Verifies CRC and actual decompression.
            if item.is_dir() and content:
                raise ValueError("directory with content: " + repr(name))
            if len(content) != item.file_size:
                raise ValueError("ZIP size mismatch: " + repr(name))
            record = {
                "path": relative,
                "directory": item.is_dir(),
                "size": len(content),
                "sha256": digest(content),
                "unix_mode": oct(item.external_attr >> 16),
            }
            records.append(record)
            seen[key] = record
        for record in records:
            path = PurePosixPath(record["path"])
            for parent in path.parents:
                if str(parent) == ".":
                    continue
                key = unicodedata.normalize("NFC", str(parent)).casefold()
                if key in seen and not seen[key]["directory"]:
                    raise ValueError("file/directory prefix conflict: " + record["path"])
    return sorted(records, key=lambda row: row["path"])


def extract_zip(archive, destination, records):
    if destination.exists() or destination.is_symlink():
        raise ValueError("extraction destination must be new: " + str(destination))
    destination.mkdir(parents=False)
    base = destination.resolve()
    with zipfile.ZipFile(archive) as package:
        by_name = {item.filename.rstrip("/"): item for item in package.infolist()}
        for record in records:
            target = destination.joinpath(*record["path"].split("/"))
            # Defense in depth: never rely only on lexical prefix comparison.
            if not target.resolve().is_relative_to(base):
                raise ValueError("member escapes extraction directory")
            if record["directory"]:
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with target.open("xb") as stream:
                    stream.write(package.read(by_name[record["path"]]))
                if int(record["unix_mode"], 8) & 0o111:
                    target.chmod(0o755)
    return base


MODULE_NAME = "BigSaltyMan/moonsize"
VERSION_PATTERN = re.compile(
    r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
)


def unique_json_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate manifest JSON field: " + key)
        value[key] = item
    return value


def valid_identity(name, version, path):
    if not isinstance(name, str) or not name or name != name.strip():
        raise ValueError("manifest name must be a nonempty string: " + str(path))
    if not isinstance(version, str) or not VERSION_PATTERN.fullmatch(version):
        raise ValueError("manifest version must be an explicit semantic version: " + str(path))
    return name, version


def module_identity(path):
    """Read exact identity assignments, never substring-match a package name.

    Only ordinary single-line string identity assignments are supported in the
    MoonBit manifest form. Unsupported or malformed identity syntax fails rather
    than guessing; the package command separately validates the full manifest.
    """
    path = Path(path)
    text = path.read_text(encoding="utf-8")
    if path.name.endswith(".json"):
        value = json.loads(text, object_pairs_hook=unique_json_object)
        if not isinstance(value, dict):
            raise ValueError("module manifest must be an object: " + str(path))
        return valid_identity(value.get("name"), value.get("version"), path)
    values = {}
    assignment = re.compile(
        r'\s*(name|version)\s*=\s*("(?:[^"\\\r\n]|\\.)*")\s*(?://[^\r\n]*)?'
    )
    for line in text.splitlines():
        if not re.match(r"\s*(?:name|version)\b", line):
            continue
        match = assignment.fullmatch(line)
        if not match:
            raise ValueError("unsupported or malformed manifest identity: " + str(path))
        key, literal = match.groups()
        if key in values:
            raise ValueError("duplicate manifest identity field " + key + ": " + str(path))
        values[key] = json.loads(literal)
    return valid_identity(values.get("name"), values.get("version"), path)


def source_identity(source, expected_version=None):
    """Obtain the expectation from the clean source, before reading the ZIP."""
    source = Path(source)
    manifests = [source / name for name in ("moon.mod", "moon.mod.json") if (source / name).is_file()]
    if not manifests:
        raise ValueError("clean source module manifest missing: " + str(source))
    identities = [module_identity(manifest) for manifest in manifests]
    identity = identities[0]
    if any(other != identity for other in identities[1:]):
        raise ValueError("clean source manifests disagree on name/version")
    if identity[0] != MODULE_NAME:
        raise ValueError("clean source module name mismatch: expected " + MODULE_NAME)
    if expected_version is not None:
        if not isinstance(expected_version, str) or not VERSION_PATTERN.fullmatch(expected_version):
            raise ValueError("invalid explicit expected version")
        if identity[1] != expected_version:
            raise ValueError("clean source version mismatch: expected " + expected_version + ", got " + identity[1])
    return identity


def check_package_identity(expected, package_manifest):
    """Compare to the source-derived identity, not to another ZIP value."""
    if not isinstance(expected, tuple) or len(expected) != 2:
        raise ValueError("source-derived identity tuple required")
    valid_identity(expected[0], expected[1], "clean source expectation")
    if expected[0] != MODULE_NAME:
        raise ValueError("source-derived module name mismatch")
    actual = module_identity(package_manifest)
    if actual != expected:
        raise ValueError(
            "package manifest identity/version mismatch: expected " + repr(expected) +
            ", got " + repr(actual) + " at " + str(package_manifest)
        )
    return actual


def excluded_member(relative):
    path = PurePosixPath(relative)
    banned = {
        "_build", ".mooncakes", "target", "node_modules", ".git",
        "review-artifacts", "_probe", ".ecoscan", "_package_audit_probe",
        "temporary-evidence", "source-package-audit-evidence", "_audit-evidence",
    }
    if any(part in banned for part in path.parts):
        return True
    if path.name == "AGENTS.md" or path.name.endswith("-plan.md"):
        return True
    if path.name.startswith("october-") and path.suffix == ".md":
        return True
    if path.parts[0] == "examples":
        if path.suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".webp", ".pdf"}:
            return True
        if path.name == "report.html" or any(part.startswith("report-update.") for part in path.parts):
            return True
    return False


def runtime_file(relative):
    path = PurePosixPath(relative)
    if excluded_member(relative):
        return False
    if any(part in {"test", "tests"} for part in path.parts):
        return False
    if path.name.endswith(("_test.mbt", "_wbtest.mbt", "_bbtest.mbt")):
        return False
    return path.suffix in {".mbt", ".c", ".h"} or path.name in {"moon.pkg", "moon.pkg.json", "moon.mod", "moon.mod.json"}


def audit(source, archive, destination, evidence):
    records = inspect_zip(archive)
    report = {
        "format": "moonsize-source-package-members",
        "schema_version": 1,
        "source_directory": str(source.resolve()),
        "zip_path": str(archive.resolve()),
        "zip_size": archive.stat().st_size,
        "zip_sha256": digest(archive.read_bytes()),
        "members": records,
        "generated_or_changed_members": [],
        "passed": False,
    }
    try:
        expected_identity = source_identity(source)
        report["expected_source_name"], report["expected_source_version"] = expected_identity
        module_members = [row["path"] for row in records if not row["directory"] and PurePosixPath(row["path"]).name in {"moon.mod", "moon.mod.json"}]
        roots = {str(PurePosixPath(name).parent) for name in module_members}
        if len(roots) != 1:
            raise ValueError("actual package must contain exactly one module root: " + repr(module_members))
        prefix = next(iter(roots))
        report["package_root_relative"] = prefix
        if prefix != "." and excluded_member(prefix):
            raise ValueError("excluded directory used as package root: " + prefix)
        relative_members = {}
        for row in records:
            path = PurePosixPath(row["path"])
            if prefix == ".":
                relative = str(path)
            else:
                try:
                    relative = str(path.relative_to(prefix))
                except ValueError as error:
                    # A ZIP may spell the directories leading to its module
                    # root explicitly; siblings outside that root are invalid.
                    if row["directory"] and path in PurePosixPath(prefix).parents:
                        continue
                    raise ValueError("member outside manifest root: " + str(path)) from error
            if relative == "." and row["directory"]:
                continue
            if excluded_member(relative):
                raise ValueError("excluded repository/build evidence in package: " + relative)
            if row["directory"]:
                if not source.joinpath(*PurePosixPath(relative).parts).is_dir():
                    raise ValueError("unexplained generated/evidence directory in package: " + relative)
                continue
            relative_members[relative] = row
        source_files = {p.relative_to(source).as_posix(): p for p in source.rglob("*") if p.is_file()}
        runtime = sorted(name for name in source_files if runtime_file(name))
        if not runtime:
            raise ValueError("source runtime inventory is empty")
        required = set(runtime)
        required.update({"LICENSE", "README.md", "README.zh.md", "docs/source-delivery.md"})
        required.update(name for name in source_files if name.startswith("assets/"))
        required.update(name for name in source_files if name.startswith("internal/compression/") and (PurePosixPath(name).name in {"LICENSE", "README.md", "provenance.json"} or "LICENSE" in PurePosixPath(name).name or "NOTICE" in PurePosixPath(name).name))
        # Direct task-oriented documentation links are package requirements too.
        delivery = source / "docs/source-delivery.md"
        if not delivery.is_file():
            raise ValueError("source delivery entry document missing")
        for link in re.findall(r'\[[^\]]*\]\(([^\s)]+)(?:\s[^)]*)?\)', delivery.read_text(encoding="utf-8")):
            link = unquote(link.strip("<>").split("#", 1)[0])
            if not link or ":" in link or not link.endswith(".md"):
                continue
            target = (delivery.parent / link).resolve()
            if not target.is_relative_to(source.resolve()):
                raise ValueError("delivery link outside source: " + link)
            required.add(target.relative_to(source.resolve()).as_posix())
        missing = sorted(required - relative_members.keys())
        report["runtime_files"] = runtime
        report["required_files"] = sorted(required)
        if missing:
            raise ValueError("actual package missing required source/resource/license/document: " + ", ".join(missing))
        changed = []
        for relative, row in relative_members.items():
            original = source_files.get(relative)
            if original is None:
                changed.append({"path": relative, "reason": "not present in clean commit export; generated conversion has not been proven equivalent"})
            elif row["sha256"] != digest(original.read_bytes()):
                changed.append({"path": relative, "reason": "content differs from original committed bytes"})
        report["generated_or_changed_members"] = changed
        if changed:
            raise ValueError("unexplained generated/changed package members: " + repr(changed))
        extract_root = extract_zip(archive, destination, records)
        package_root = extract_root if prefix == "." else extract_root / prefix
        report["package_root"] = str(package_root)
        manifests = [package_root / PurePosixPath(name).name for name in module_members]
        for manifest in manifests:
            check_package_identity(expected_identity, manifest)
        report["manifest_name"], report["manifest_version"] = expected_identity
        # Raw-byte checks cover all source metadata; these checks make the
        # native-only CLI and its C stub requirements separately reviewable.
        pkg = package_root / "cmd/main/moon.pkg"
        config = pkg.read_text(encoding="utf-8")
        if '"native-stub"' not in config or '"output_native.c"' not in config or '"+native"' not in config:
            raise ValueError("native CLI configuration is incomplete")
        report["native_stub_configuration"] = "cmd/main/moon.pkg references output_native.c and +native"
        report["runtime_file_count"] = len(runtime)
        report["file_count"] = len(relative_members)
        report["passed"] = True
    except Exception as error:
        report["error"] = str(error)
        raise
    finally:
        evidence.mkdir(parents=True, exist_ok=True)
        save(evidence / "members.json", report)
    return report


def main():
    args = sys.argv[1:]
    if len(args) == 3 and args[0] == "extract":
        archive, destination = map(Path, args[1:])
        records = inspect_zip(archive)
        extracted = extract_zip(archive, destination, records)
        print(json.dumps({"destination": str(extracted), "members": len(records)}, ensure_ascii=False))
    elif len(args) == 5 and args[0] == "audit":
        print(json.dumps(audit(*map(Path, args[1:])), ensure_ascii=False))
    elif len(args) in (2, 3) and args[0] == "identity":
        name, version = source_identity(Path(args[1]), args[2] if len(args) == 3 else None)
        print(json.dumps({"name": name, "version": version}, ensure_ascii=False))
    else:
        raise ValueError("usage: audit-source-package.py extract ZIP NEW_DIR | audit SOURCE ZIP NEW_DIR EVIDENCE | identity SOURCE [EXPECTED_VERSION]")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("source package ZIP audit failed: " + str(error), file=sys.stderr)
        sys.exit(1)
