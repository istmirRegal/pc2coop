"""Documentation matches the code (FEAT-221, tools/check_docs.py)."""
from pathlib import Path
import importlib.util
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("check_docs", ROOT / "tools" / "check_docs.py")
check_docs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_docs)


class DocsMatchCode(unittest.TestCase):
    def test_docs_match_code(self):
        problems = check_docs.check()
        self.assertEqual(problems, [], "\n" + "\n".join(problems))

    def test_registry_check_finds_gaps(self):
        registry = ("## A — [features/a.md](../features/a.md)\n"
                    "| FEAT-001 | Eins | Implemented | 1.0 |\n"
                    "| FEAT-002 | Zwei | Kaputt | 1.0 |\n")
        features = {"a.md": "### FEAT-001 – Eins\n- **Status:** Removed\n### FEAT-003 – Drei\n- **Status:** Planned\n"}
        problems = "\n".join(check_docs.check_registry(registry, features))
        self.assertIn("FEAT-001: status 'Implemented' in FEATURES.md but 'Removed'", problems)
        self.assertIn("FEAT-002 has unknown status 'Kaputt'", problems)
        self.assertIn("FEAT-002: no '### FEAT-002' section", problems)
        self.assertIn("FEAT-003: section in a.md but not in FEATURES.md", problems)

    def test_path_and_function_checks_find_stale_names(self):
        texts = {"x.md": "See `tools/does_not_exist.py` and `Session.NoSuchFunction` but `Session.Host` is fine."}
        self.assertEqual(check_docs.check_paths(texts), ["x.md:1: path `tools/does_not_exist.py` does not exist"])
        self.assertEqual(check_docs.check_functions(texts), ["x.md:1: `Session.NoSuchFunction` is not defined in the Lua code"])

    def test_code_scan_finds_something(self):
        # A rename in the code must not make the coverage checks silently empty.
        self.assertIn("hello", check_docs.wire_kinds())
        self.assertIn("visitor", check_docs.dll_verbs())
        self.assertIn("net:ready", check_docs.dll_events())
        self.assertIn("buy", check_docs.ui_actions())
        self.assertIn("new-test-park", check_docs.qa_commands())


if __name__ == "__main__":
    unittest.main()
