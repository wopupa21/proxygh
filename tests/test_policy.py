from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "nginx" / "proxygh.conf.template"
COMMON = ROOT / "nginx" / "proxygh-common.conf"
ZONES = ROOT / "nginx" / "proxygh-zones.conf"


class NginxPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.site = SITE.read_text(encoding="utf-8")
        cls.common = COMMON.read_text(encoding="utf-8")
        cls.zones = ZONES.read_text(encoding="utf-8")
        cls.all_config = "\n".join((cls.site, cls.common, cls.zones))

    def test_template_has_exact_render_tokens(self):
        self.assertIn("__PROXYGH_DOMAIN__", self.site)
        self.assertIn("__PROXYGH_CERTIFICATE__", self.site)
        self.assertIn("__PROXYGH_CERTIFICATE_KEY__", self.site)

    def test_only_documented_github_upstreams_are_used(self):
        proxy_passes = re.findall(r"proxy_pass\s+(https://[^;]+);", self.site)
        self.assertEqual(
            set(proxy_passes),
            {
                "https://github.com",
                "https://raw.githubusercontent.com",
                "https://codeload.github.com",
                "https://release-assets.githubusercontent.com",
            },
        )
        self.assertNotRegex(self.site, r"proxy_pass\s+https?://\$")
        self.assertNotIn("$arg_url", self.site)
        self.assertNotIn("$http_host", self.site)

    def test_authentication_covers_https_server(self):
        self.assertRegex(
            self.site,
            r"listen 443 ssl http2;[\s\S]+?auth_basic \"ProxyGH\";[\s\S]+?auth_basic_user_file /etc/nginx/proxygh.htpasswd;",
        )

    def test_proxy_credentials_are_never_forwarded(self):
        route_count = len(re.findall(r"proxy_pass\s+https://", self.site))
        strip_count = len(
            re.findall(r"include /etc/nginx/snippets/proxygh-common.conf;", self.site)
        )
        self.assertEqual(strip_count, route_count)
        self.assertIn('proxy_set_header Authorization "";', self.common)
        self.assertIn('proxy_set_header Cookie "";', self.common)

    def test_routes_restrict_methods_and_push(self):
        self.assertGreaterEqual(self.site.count("limit_except GET HEAD"), 3)
        self.assertIn("limit_except GET HEAD POST", self.site)
        self.assertIn('$arg_service = "git-receive-pack"', self.site)
        self.assertRegex(self.site, r"location ~ \^/git/.+/git-receive-pack\$")

    def test_release_redirects_are_allowlisted_and_same_origin(self):
        self.assertIn(
            r"proxy_redirect ~^https://release-assets\.githubusercontent\.com/(.*)$ https://__PROXYGH_DOMAIN__/_release_asset/$1;",
            self.site,
        )
        self.assertIn(
            "proxy_redirect https://github.com/ https://__PROXYGH_DOMAIN__/release/;",
            self.site,
        )
        self.assertIn("location ^~ /_release_asset/", self.site)
        self.assertNotIn("proxy_redirect default", self.site)
        self.assertIn(
            r"proxy_redirect ~^(/.*)$ https://__PROXYGH_DOMAIN__/release$1;",
            self.site,
        )

    def test_git_relative_redirects_keep_the_proxy_prefix(self):
        self.assertIn(
            r"proxy_redirect ~^(/.*)$ https://__PROXYGH_DOMAIN__/git$1;",
            self.site,
        )

    def test_streaming_has_no_proxy_cache(self):
        self.assertIn("proxy_buffering off;", self.common)
        self.assertIn("proxy_max_temp_file_size 0;", self.common)
        self.assertIn("proxy_buffer_size 32k;", self.common)
        self.assertIn("proxy_buffers 8 32k;", self.common)
        self.assertNotIn("proxy_cache_path", self.all_config)
        self.assertNotRegex(self.all_config, r"(?m)^\s*proxy_cache\s+")

    def test_tls_verification_and_sni_are_enabled(self):
        self.assertIn("proxy_ssl_server_name on;", self.common)
        self.assertIn("proxy_ssl_verify on;", self.common)
        self.assertIn(
            "proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;",
            self.common,
        )

    def test_rate_and_connection_limits_are_declared_and_used(self):
        self.assertIn("limit_req_zone $binary_remote_addr zone=proxygh_rate", self.zones)
        self.assertIn("limit_conn_zone $binary_remote_addr zone=proxygh_conn", self.zones)
        self.assertIn("limit_req zone=proxygh_rate", self.site)
        self.assertIn("limit_conn proxygh_conn", self.site)

    def test_access_log_omits_query_strings_and_auth_headers(self):
        self.assertIn("log_format proxygh", self.zones)
        self.assertIn("$uri", self.zones)
        self.assertNotIn("$request_uri", self.zones)
        self.assertNotIn("$args", self.zones)
        self.assertNotIn("$http_authorization", self.zones)


if __name__ == "__main__":
    unittest.main()
