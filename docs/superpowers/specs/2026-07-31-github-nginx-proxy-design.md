# GitHub Nginx Proxy Design

## Goal

Deploy an authenticated, no-cache GitHub download proxy on a Japan-hosted
Debian 11 or 12 server. It serves a few trusted users in mainland China and
supports public Git repositories, Raw files, source archives, and Release
assets. It does not proxy GitHub web browsing, login, private repositories,
push, Git LFS, Packages, GHCR, or arbitrary URLs.

## Architecture

One HTTPS hostname exposes four fixed prefixes:

| Prefix | Fixed upstream | Methods |
| --- | --- | --- |
| `/git/` | `github.com` | `GET`, `HEAD`, `POST` |
| `/raw/` | `raw.githubusercontent.com` | `GET`, `HEAD` |
| `/archive/` | `codeload.github.com` | `GET`, `HEAD` |
| `/release/` | `github.com` | `GET`, `HEAD` |

Release responses may redirect to GitHub's documented
`release-assets.githubusercontent.com` hostname. Nginx rewrites only that
exact hostname back to a protected local asset route and then streams the
signed path and query to the fixed asset upstream. No request input controls
an upstream hostname.

## Security And Operations

- Require HTTP Basic Authentication on every proxy route and create one
  htpasswd user per person.
- Strip the incoming `Authorization` header before proxying so proxy
  credentials never reach GitHub.
- Restrict methods, block Git receive-pack, limit per-IP request rate and
  concurrent connections, and log sanitized URIs without query strings.
- Verify upstream TLS certificates with Debian's CA bundle and send the
  correct Host and SNI values.
- Do not add CORS headers or remove upstream security headers.
- Do not configure `proxy_cache`. Disable proxy buffering so large responses
  stream without proxy temporary files. Preserve Range and validators for
  resumable downloads.
- Use the operator's existing wildcard certificate by default. Document a
  Certbot HTTP-01 flow for a single hostname and DNS-01 requirements for a
  wildcard certificate, including renewal dry runs and Nginx reload hooks.

## Deliverables

- A parameterized Nginx site template and shared rate-limit zone config.
- An idempotent Debian installer that backs up conflicting managed files.
- A user-management helper and an authenticated smoke-test helper.
- Static policy tests and CI checks.
- A Chinese README covering prerequisites, DNS, certificates, deployment,
  client usage, upgrades, removal, troubleshooting, and limitations.

## Acceptance Criteria

- Unauthenticated proxy requests return 401.
- Authenticated Git clone/fetch, Raw, archive, and Release downloads work.
- Release redirects stay on the proxy hostname and only reach the fixed
  documented asset upstream.
- Range requests produce a partial response when GitHub supports it.
- Large responses are streamed without a configured cache.
- Static checks prove fixed upstreams, auth coverage, stripped upstream auth,
  restricted methods, sanitized logging, and no generic URL proxy.
- `nginx -t` passes on the target Debian server before reload.

## Sources

- https://nginx.org/en/docs/http/ngx_http_proxy_module.html
- https://docs.github.com/en/repositories/creating-and-managing-repositories/cloning-a-repository
- https://docs.github.com/en/repositories/working-with-files/using-files/downloading-source-code-archives
- https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases
- https://docs.github.com/en/actions/reference/runners/self-hosted-runners
- https://eff-certbot.readthedocs.io/en/stable/using.html
