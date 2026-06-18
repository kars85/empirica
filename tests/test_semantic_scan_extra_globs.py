"""Tests for project-configurable scan globs in semantic_scan.

The built-in SCAN_RULES are tuned to Empirica's own layout. Consuming
projects (e.g. a Next.js app with docs under web/) can extend the scan via
.empirica/project.yaml `semantic_scan.extra_globs` without editing core.

Surface tested: _load_extra_scan_rules, _effective_scan_rules, scan_project,
newest_source_mtime — all honor the extra globs, and a missing/malformed
config degrades to built-in-only behavior (never raises).
"""

from __future__ import annotations

import textwrap

from empirica.core.docs import semantic_scan as ss


def _make_project(tmp_path, *, with_config: bool, config_text: str = "") -> None:
    """Build a fake project: a repo-root doc (built-in glob) + a web/docs doc
    (only reachable via extra_globs)."""
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "root-doc.md").write_text(
        "# Root Doc\n\n" + "x" * 200, encoding="utf-8"
    )
    web_docs = tmp_path / "web" / "docs"
    web_docs.mkdir(parents=True)
    (web_docs / "compliance.md").write_text(
        "# Compliance Engine\n\n" + "y" * 200, encoding="utf-8"
    )
    (tmp_path / "web" / "CLAUDE.md").write_text(
        "# Web Instructions\n\n" + "z" * 200, encoding="utf-8"
    )
    if with_config:
        empirica_dir = tmp_path / ".empirica"
        empirica_dir.mkdir()
        (empirica_dir / "project.yaml").write_text(
            textwrap.dedent(config_text), encoding="utf-8"
        )


_EXTRA_CONFIG = """
    project_id: test-1234
    semantic_scan:
      extra_globs:
        - glob: "web/docs/**/*.md"
          doc_type: web-docs
          tags: [web, documentation]
        - glob: "web/**/CLAUDE.md"
          doc_type: web-instructions
          tags: [web, instructions]
"""


def test_no_config_is_builtin_only(tmp_path):
    """No .empirica/project.yaml → only built-in rules; web/docs NOT scanned."""
    _make_project(tmp_path, with_config=False)
    assert ss._load_extra_scan_rules(tmp_path) == ()
    entries = ss.scan_project(tmp_path)
    assert "docs\\root-doc.md" in entries or "docs/root-doc.md" in entries
    assert not any("web" in key for key in entries), entries


def test_extra_globs_reach_web_docs(tmp_path):
    """extra_globs makes web/docs/**/*.md and web/**/CLAUDE.md scannable."""
    _make_project(tmp_path, with_config=True, config_text=_EXTRA_CONFIG)
    entries = ss.scan_project(tmp_path)
    keys = {k.replace("\\", "/") for k in entries}
    assert "web/docs/compliance.md" in keys
    assert "web/CLAUDE.md" in keys
    # built-in repo-root doc still present
    assert "docs/root-doc.md" in keys
    # extra rule's doc_type + tags applied
    assert entries[next(k for k in entries if k.replace("\\", "/") == "web/docs/compliance.md")]["doc_type"] == "web-docs"


def test_extra_rules_parsed_with_tags_and_doc_type(tmp_path):
    _make_project(tmp_path, with_config=True, config_text=_EXTRA_CONFIG)
    rules = ss._load_extra_scan_rules(tmp_path)
    assert len(rules) == 2
    assert rules[0].glob == "web/docs/**/*.md"
    assert rules[0].doc_type == "web-docs"
    assert rules[0].base_tags == ("web", "documentation")


def test_effective_rules_append_extras_after_builtins(tmp_path):
    _make_project(tmp_path, with_config=True, config_text=_EXTRA_CONFIG)
    effective = ss._effective_scan_rules(tmp_path)
    assert effective[: len(ss.SCAN_RULES)] == ss.SCAN_RULES
    assert len(effective) == len(ss.SCAN_RULES) + 2


def test_malformed_config_degrades_to_builtins(tmp_path):
    """Garbage config never raises; falls back to built-in-only."""
    _make_project(tmp_path, with_config=True, config_text="semantic_scan: [not, a, dict]\n")
    assert ss._load_extra_scan_rules(tmp_path) == ()
    entries = ss.scan_project(tmp_path)  # must not raise
    assert not any("web" in key for key in entries)


def test_newest_source_mtime_honors_extra_globs(tmp_path):
    """Staleness signal must walk extra globs too, else cache never refreshes
    when only a web/ doc changes."""
    _make_project(tmp_path, with_config=True, config_text=_EXTRA_CONFIG)
    baseline = ss.newest_source_mtime(tmp_path)
    # make a web doc the newest file
    newer = tmp_path / "web" / "docs" / "compliance.md"
    st = newer.stat()
    import os
    os.utime(newer, (st.st_atime, st.st_mtime + 10_000))
    assert ss.newest_source_mtime(tmp_path) > baseline
