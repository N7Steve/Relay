import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import release_local  # noqa: E402

COMMIT = "a" * 40


class PackageAndroidTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        (self.dir / "app-release.apk").write_bytes(b"signed apk")
        self.metadata = {
            "applicationId": "app.relay.android",
            "elements": [{"outputFile": "app-release.apk", "versionCode": 4321, "versionName": "0.1.4321"}],
            "minSdkVersionForDexing": 26,
        }

    def package(self):
        path = self.dir / "output-metadata.json"
        path.write_text(json.dumps(self.metadata))
        return release_local.package_android(path, COMMIT, self.dir / "out")

    def test_writes_the_manifest_the_server_serves(self):
        release = self.package()
        self.assertEqual(release, json.loads((self.dir / "out/update.json").read_text()))
        self.assertEqual(b"signed apk", (self.dir / "out/relay.apk").read_bytes())
        self.assertEqual({"version_code", "version_name", "application_id", "min_sdk", "size", "sha256", "commit"}, set(release))
        self.assertEqual(10, release["size"])
        self.assertEqual(COMMIT, release["commit"])

    def test_rejects_another_application(self):
        self.metadata["applicationId"] = "am.sure.mobile"
        with self.assertRaises(ValueError):
            self.package()

    def test_rejects_an_unsigned_apk(self):
        (self.dir / "app-release-unsigned.apk").write_bytes(b"x")
        self.metadata["elements"][0]["outputFile"] = "app-release-unsigned.apk"
        with self.assertRaises(ValueError):
            self.package()

    def test_rejects_split_outputs(self):
        self.metadata["elements"].append(dict(self.metadata["elements"][0]))
        with self.assertRaises(ValueError):
            self.package()


class VersionTest(unittest.TestCase):
    def test_version_follows_the_commit_count(self):
        self.assertEqual((5120, "0.1.5120"), release_local.version_for(5120))

    def test_rejects_an_empty_history(self):
        with self.assertRaises(ValueError):
            release_local.version_for(0)


if __name__ == "__main__":
    unittest.main()
