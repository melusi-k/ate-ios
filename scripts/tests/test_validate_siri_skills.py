import tempfile
import unittest
from pathlib import Path

from validate_siri_skills import parse_skill, validate_bundle


class SiriSkillValidationTests(unittest.TestCase):
    def write_skill(self, root: Path, name: str = "example-skill", body: str = "Do the task."):
        skill_dir = root / "Skills" / name
        skill_dir.mkdir(parents=True, exist_ok=True)
        skill_file = skill_dir / "SKILL.md"
        skill_file.write_text(
            f"---\nname: {name}\ndescription: A one-line description.\n---\n\n{body}\n",
            encoding="utf-8",
        )
        return skill_dir, skill_file

    def test_valid_bundle(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.write_skill(root)
            self.assertEqual(validate_bundle(root), ["Skills/example-skill/SKILL.md"])

    def test_rejects_name_that_does_not_match_folder(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _, path = self.write_skill(root)
            path.write_text(
                "---\nname: another-skill\ndescription: A one-line description.\n---\n\nBody",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "must match directory"):
                validate_bundle(root)

    def test_rejects_unsupported_front_matter(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _, path = self.write_skill(root)
            path.write_text(
                "---\nname: example-skill\ndescription: Description.\nauthor: Ate\n---\n\nBody",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "unsupported front matter key"):
                validate_bundle(root)

    def test_rejects_long_description(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _, path = self.write_skill(root)
            path.write_text(
                "---\nname: example-skill\ndescription: " + ("x" * 1025) + "\n---\n\nBody",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "at most 1,024"):
                validate_bundle(root)

    def test_rejects_body_over_limit(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _, path = self.write_skill(root, body="x" * 10001)
            with self.assertRaisesRegex(ValueError, "exceeds 10,000"):
                validate_bundle(root)

    def test_rejects_extra_files_in_skill_folder(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            skill_dir, _ = self.write_skill(root)
            (skill_dir / "notes.txt").write_text("not supported", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "unsupported extra files"):
                validate_bundle(root)


if __name__ == "__main__":
    unittest.main()
