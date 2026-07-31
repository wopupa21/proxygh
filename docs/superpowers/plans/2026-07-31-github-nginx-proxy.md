# GitHub Nginx Proxy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a secure, authenticated, no-cache Nginx proxy for public GitHub Git, Raw, archive, and Release downloads on Debian 11/12.

**Architecture:** A single HTTPS virtual host routes fixed path prefixes to fixed GitHub upstreams. Release redirects are rewritten to a same-origin protected route whose only upstream is `release-assets.githubusercontent.com`; installation and user-management scripts render and operate the configuration without accepting arbitrary upstreams.

**Tech Stack:** Nginx, POSIX-compatible Bash, Debian packages, Python 3 `unittest`, GitHub Actions.

## Global Constraints

- Support Debian 11 and 12 with an existing Nginx installation.
- Serve only public GitHub Git read operations, Raw files, source archives, and Release assets.
- Require Basic Auth, strip `Authorization` upstream, and never accept a user-controlled upstream hostname.
- Do not use Cloudflare, proxy caching, HTML rewriting, permissive CORS, GitHub login, private repositories, push, Git LFS, Packages, or GHCR.
- Stream downloads and preserve Range behavior.
- Use one hostname with `/git/`, `/raw/`, `/archive/`, and `/release/` routes.

---

### Task 1: Nginx Policy Templates

**Files:**
- Create: `nginx/proxygh-zones.conf`
- Create: `nginx/proxygh-common.conf`
- Create: `nginx/proxygh.conf.template`
- Test: `tests/test_policy.py`

**Interfaces:**
- Consumes: `__PROXYGH_DOMAIN__`, `__PROXYGH_CERTIFICATE__`, and `__PROXYGH_CERTIFICATE_KEY__` render tokens.
- Produces: Debian Nginx files installed under `/etc/nginx/conf.d`, `/etc/nginx/snippets`, and `/etc/nginx/sites-available`.

- [ ] **Step 1: Write failing policy tests**

Create `tests/test_policy.py` assertions for all fixed upstreams, server-wide auth, `proxy_set_header Authorization ""`, method restrictions, receive-pack blocking, Release redirect allowlisting, `proxy_buffering off`, absence of `proxy_cache_path`, and sanitized logging without `$request_uri` or `$args`.

- [ ] **Step 2: Run tests and verify failure**

Run: `python -m unittest discover -s tests -v`
Expected: FAIL because the Nginx templates do not exist.

- [ ] **Step 3: Implement the templates**

Define binary-address rate and connection zones, shared TLS/streaming proxy settings, an HTTP ACME/redirect server, an HTTPS authenticated server, fixed route rewrites, a blocked receive-pack location, and the exact Release asset redirect rewrite.

- [ ] **Step 4: Run tests and verify success**

Run: `python -m unittest discover -s tests -v`
Expected: PASS for all Nginx policy tests.

### Task 2: Debian Operations Scripts

**Files:**
- Create: `scripts/install.sh`
- Create: `scripts/add-user.sh`
- Create: `scripts/smoke-test.sh`
- Test: `tests/test_scripts.py`

**Interfaces:**
- Consumes: the three template tokens and files from Task 1.
- Produces: `install.sh --domain --certificate --certificate-key`, `add-user.sh USERNAME`, and `smoke-test.sh --domain --user`.

- [ ] **Step 1: Write failing script-contract tests**

Assert strict shell mode, root and argument checks, domain/path validation, managed-file backup, htpasswd bcrypt use, `nginx -t` before reload, and smoke-test coverage for 401, Raw, archive, Release headers, Range, and Git refs.

- [ ] **Step 2: Run tests and verify failure**

Run: `python -m unittest discover -s tests -v`
Expected: FAIL because the scripts do not exist.

- [ ] **Step 3: Implement the scripts**

Use only fixed destination paths, quote all variables, install required Debian packages unless skipped, back up existing managed files, render with escaped replacement values, preserve an existing htpasswd file, validate before reload, and keep passwords interactive.

- [ ] **Step 4: Run tests and shell syntax checks**

Run: `python -m unittest discover -s tests -v` and `bash -n scripts/*.sh`
Expected: all tests pass and Bash reports no syntax errors.

### Task 3: Documentation And Continuous Integration

**Files:**
- Modify: `README.md`
- Create: `.github/workflows/ci.yml`
- Create: `.gitignore`

**Interfaces:**
- Consumes: exact commands and limitations implemented by Tasks 1 and 2.
- Produces: an end-to-end Chinese deployment guide and automated policy/shell checks.

- [ ] **Step 1: Write the complete deployment guide**

Document architecture, Debian detection, DNS, firewall, wildcard certificate installation, optional Certbot HTTP-01 and DNS-01 renewal, install and user commands, client Git/curl examples, credential helpers, smoke tests, logs, upgrades, rollback/removal, limitations, and security warnings.

- [ ] **Step 2: Add CI**

Run Python unit tests and ShellCheck on pushes and pull requests using Ubuntu's packaged `shellcheck`.

- [ ] **Step 3: Verify documentation commands match scripts**

Run repository searches for every documented script option and route, then run the full test suite and syntax checks.
Expected: commands and paths agree; all checks pass.

### Task 4: Final Verification And Publication

**Files:**
- Review: all tracked files

**Interfaces:**
- Consumes: the completed repository.
- Produces: a reviewed commit pushed to `wopupa21/proxygh` on `main`.

- [ ] **Step 1: Run final verification**

Run: `python -m unittest discover -s tests -v`, `bash -n scripts/*.sh`, ShellCheck when available, and an Nginx syntax test when a local Nginx binary is available.
Expected: all available checks pass; unavailable environment-dependent checks are explicitly reported.

- [ ] **Step 2: Review the diff for secrets and destructive behavior**

Search for passwords, tokens, private keys, user-controlled proxy targets, unsafe deletion, and accidental generated files.
Expected: no secrets or unsafe generic proxy behavior.

- [ ] **Step 3: Commit and push**

Run: `git add .`, `git commit -m "feat: add secure GitHub Nginx proxy"`, and `git push origin main`.
Expected: GitHub accepts the commit and local `main` matches `origin/main`.
