from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
INSTALL = ROOT / "scripts" / "install.sh"
ADD_USER = ROOT / "scripts" / "add-user.sh"
SMOKE = ROOT / "scripts" / "smoke-test.sh"
REQUEST_CERT = ROOT / "scripts" / "request-certificate.sh"


class ScriptContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.install = INSTALL.read_text(encoding="utf-8")
        cls.add_user = ADD_USER.read_text(encoding="utf-8")
        cls.smoke = SMOKE.read_text(encoding="utf-8")
        cls.request_cert = REQUEST_CERT.read_text(encoding="utf-8")

    def test_all_scripts_use_strict_mode(self):
        for content in (self.install, self.add_user, self.smoke, self.request_cert):
            self.assertIn("set -Eeuo pipefail", content)

    def test_installer_checks_root_and_required_arguments(self):
        self.assertIn("EUID", self.install)
        self.assertIn("--domain", self.install)
        self.assertIn("--certificate", self.install)
        self.assertIn("--certificate-key", self.install)
        self.assertIn("validate_domain", self.install)
        self.assertIn("validate_absolute_path", self.install)
        self.assertLess(self.install.index("== --help"), self.install.index("EUID"))

    def test_installer_backs_up_and_validates_before_reload(self):
        self.assertIn("backup_file", self.install)
        self.assertIn("BACKUP_ROOT=/etc/nginx/proxygh-backups", self.install)
        self.assertNotIn('backup="${destination}.proxygh-backup-', self.install)
        self.assertLess(self.install.index("nginx -t"), self.install.index("reload nginx"))

    def test_user_helper_uses_bcrypt_and_validates_username(self):
        self.assertIn("validate_username", self.add_user)
        self.assertIn("htpasswd -B", self.add_user)
        self.assertIn("htpasswd -cB", self.add_user)
        self.assertIn("chmod 640", self.add_user)

    def test_smoke_test_covers_supported_flows(self):
        for expected in (
            "expected unauthenticated status 401",
            "/raw/",
            "/archive/",
            "/release/",
            "Range: bytes=0-0",
            "git ls-remote",
        ):
            self.assertIn(expected, self.smoke)

    def test_smoke_test_does_not_put_password_in_url(self):
        self.assertNotIn("https://${USER}:${PASSWORD}@", self.smoke)
        self.assertNotIn('--user "${USER}:${PASSWORD}"', self.smoke)
        self.assertIn("curl --config -", self.smoke)
        self.assertIn("GIT_ASKPASS", self.smoke)

    def test_certificate_helper_uses_http01_and_restores_bootstrap_site(self):
        self.assertIn("--domain", self.request_cert)
        self.assertIn("--email", self.request_cert)
        self.assertIn("certbot certonly --webroot", self.request_cert)
        self.assertIn("trap cleanup EXIT", self.request_cert)
        self.assertIn("nginx -t", self.request_cert)
        self.assertIn("systemctl reload nginx", self.request_cert)
        self.assertIn("mktemp --suffix=.conf /etc/nginx/sites-available/proxygh-acme-bootstrap.XXXXXX", self.request_cert)
        self.assertNotIn("BACKUP=", self.request_cert)
        self.assertLess(
            self.request_cert.index("== --help"), self.request_cert.index("EUID")
        )


if __name__ == "__main__":
    unittest.main()
