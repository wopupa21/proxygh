#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
usage() { printf 'Usage: sudo %s --domain gh.example.com --email admin@example.com\n' "$0"; }
validate_domain() {
    [[ $1 =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]] || die "invalid hostname: $1"
}

DOMAIN=
EMAIL=
if [[ ${1:-} == -h || ${1:-} == --help ]]; then
    usage
    exit 0
fi
[[ ${EUID:-$(id -u)} -eq 0 ]] || die "run this command as root"

while [[ $# -gt 0 ]]; do
    case $1 in
        --domain) [[ $# -ge 2 ]] || die "--domain requires a value"; DOMAIN=$2; shift 2 ;;
        --email) [[ $# -ge 2 ]] || die "--email requires a value"; EMAIL=$2; shift 2 ;;
        *) die "unknown argument: $1" ;;
    esac
done
[[ -n $DOMAIN && -n $EMAIL ]] || { usage >&2; die "--domain and --email are required"; }
validate_domain "$DOMAIN"
[[ $EMAIL == *@*.* ]] || die "invalid email address"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y certbot
install -d -m 0755 /var/www/proxygh-acme/.well-known/acme-challenge
install -d -m 0755 /etc/nginx/sites-available /etc/nginx/sites-enabled

BOOTSTRAP=$(mktemp --suffix=.conf /etc/nginx/sites-available/proxygh-acme-bootstrap.XXXXXX)
BOOTSTRAP_LINK=/etc/nginx/sites-enabled/$(basename -- "$BOOTSTRAP")

cleanup() {
    rm -f -- "$BOOTSTRAP_LINK" "$BOOTSTRAP"
    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx || true
    fi
}
trap cleanup EXIT

cat >"$BOOTSTRAP" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/proxygh-acme;
        try_files \$uri =404;
    }
    location / { return 404; }
}
EOF
ln -s "$BOOTSTRAP" "$BOOTSTRAP_LINK"
nginx -t
systemctl reload nginx

certbot certonly --webroot -w /var/www/proxygh-acme \
    -d "$DOMAIN" -m "$EMAIL" --agree-tos --no-eff-email

install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
cat >/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
nginx -t
systemctl reload nginx
EOF
chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

printf 'Certificate: /etc/letsencrypt/live/%s/fullchain.pem\n' "$DOMAIN"
printf 'Private key: /etc/letsencrypt/live/%s/privkey.pem\n' "$DOMAIN"
printf 'After installation, verify renewal with: sudo certbot renew --dry-run\n'
