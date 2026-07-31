#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
usage() { printf 'Usage: %s --domain gh.example.com --user USERNAME\n' "$0"; }

DOMAIN=
USER=
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain) [[ $# -ge 2 ]] || die "--domain requires a value"; DOMAIN=$2; shift 2 ;;
        --user) [[ $# -ge 2 ]] || die "--user requires a value"; USER=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done
[[ -n $DOMAIN && -n $USER ]] || { usage >&2; die "--domain and --user are required"; }
read -r -s -p "Password for ${USER}: " PASSWORD
printf '\n'
BASE="https://${DOMAIN}"
RELEASE_PATH="BurntSushi/ripgrep/releases/download/13.0.0/ripgrep-13.0.0-x86_64-unknown-linux-musl.tar.gz"

status=$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/raw/octocat/Hello-World/master/README")
[[ $status == 401 ]] || die "expected unauthenticated status 401, got $status"
printf 'PASS unauthenticated request: 401\n'

escape_curl_config() { printf '%s' "$1" | sed 's/[\"]/\\&/g'; }
CURL_USER=$(escape_curl_config "$USER")
CURL_PASSWORD=$(escape_curl_config "$PASSWORD")
curl_auth() {
    printf 'user = "%s:%s"\n' "$CURL_USER" "$CURL_PASSWORD" |
        curl --config - --fail --silent --show-error "$@"
}
curl_auth "$BASE/raw/octocat/Hello-World/master/README" -o /dev/null
printf 'PASS /raw/\n'
curl_auth --location "$BASE/archive/octocat/Hello-World/zip/master" -o /dev/null
printf 'PASS /archive/\n'
curl_auth --location "$BASE/release/$RELEASE_PATH" -o /dev/null
printf 'PASS /release/\n'

range_status=$(curl_auth --location -H 'Range: bytes=0-0' -o /dev/null -w '%{http_code}' \
    "$BASE/release/$RELEASE_PATH")
[[ $range_status == 206 ]] || die "expected Range status 206, got $range_status"
printf 'PASS Range: bytes=0-0 returned 206\n'

ASKPASS=$(mktemp)
cleanup() { rm -f -- "$ASKPASS"; unset PROXYGH_PASSWORD PROXYGH_USER PASSWORD; }
trap cleanup EXIT
cat >"$ASKPASS" <<'EOF'
#!/usr/bin/env bash
case $1 in
    *Username*) printf '%s\n' "$PROXYGH_USER" ;;
    *) printf '%s\n' "$PROXYGH_PASSWORD" ;;
esac
EOF
chmod 0700 "$ASKPASS"
export GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0 PROXYGH_USER="$USER" PROXYGH_PASSWORD="$PASSWORD"
git ls-remote "$BASE/git/octocat/Hello-World.git" HEAD >/dev/null
printf 'PASS git ls-remote\n'
printf 'All ProxyGH smoke tests passed.\n'
