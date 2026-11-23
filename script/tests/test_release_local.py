import email.message
import io
import json
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

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


class PrivateRegistryTest(unittest.TestCase):
    def _http_error(self, url, code, headers=None):
        hdrs = email.message.Message()
        for key, value in (headers or {}).items():
            hdrs[key] = value
        return urllib.error.HTTPError(url, code, "Error", hdrs, None)

    def test_private_image_rejects_anonymous_access(self):
        image = f"{release_local.IMAGE}:sha-test"
        challenge = {
            "WWW-Authenticate": 'Bearer realm="http://100.81.25.109:30008/v2/token",service="container_registry",scope="repository:n7steve/relay:pull"'
        }
        with patch.object(
            release_local.urllib.request,
            "urlopen",
            side_effect=[
                self._http_error("http://100.81.25.109:30008/v2/", 401, challenge),
                self._http_error("http://100.81.25.109:30008/v2/token", 401),
            ],
        ):
            release_local.verify_private_image(image)
        with patch.object(
            release_local.urllib.request,
            "urlopen",
            side_effect=[
                self._http_error("http://100.81.25.109:30008/v2/", 401, challenge),
                io.BytesIO(b'{"token":"anonymous-token"}'),
                io.BytesIO(b"{}"),
            ],
        ):
            with self.assertRaisesRegex(RuntimeError, "sin autenticar"):
                release_local.verify_private_image(image)


if __name__ == "__main__":
    unittest.main()
