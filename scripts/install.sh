#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: sudo ./scripts/install.sh --domain gh.example.com \
  --certificate /path/to/fullchain.pem \
  --certificate-key /path/to/privkey.pem [--skip-packages]
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

validate_domain() {
    [[ $1 =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]] ||
        die "invalid DNS hostname: $1"
}

validate_absolute_path() {
    local label=$1 path=$2
    [[ $path == /* ]] || die "$label must be an absolute path"
    [[ -f $path ]] || die "$label does not exist or is not a file: $path"
}

DOMAIN=
CERTIFICATE=
CERTIFICATE_KEY=
SKIP_PACKAGES=0
if [[ ${1:-} == -h || ${1:-} == --help ]]; then
    usage
    exit 0
fi
[[ ${EUID:-$(id -u)} -eq 0 ]] || die "run this installer as root"

while [[ $# -gt 0 ]]; do
    case $1 in
        --domain) [[ $# -ge 2 ]] || die "--domain requires a value"; DOMAIN=$2; shift 2 ;;
        --certificate) [[ $# -ge 2 ]] || die "--certificate requires a value"; CERTIFICATE=$2; shift 2 ;;
        --certificate-key) [[ $# -ge 2 ]] || die "--certificate-key requires a value"; CERTIFICATE_KEY=$2; shift 2 ;;
        --skip-packages) SKIP_PACKAGES=1; shift ;;
        *) die "unknown argument: $1" ;;
    esac
done

[[ -n $DOMAIN ]] || { usage >&2; die "--domain is required"; }
[[ -n $CERTIFICATE ]] || { usage >&2; die "--certificate is required"; }
[[ -n $CERTIFICATE_KEY ]] || { usage >&2; die "--certificate-key is required"; }
validate_domain "$DOMAIN"
validate_absolute_path "certificate" "$CERTIFICATE"
validate_absolute_path "certificate key" "$CERTIFICATE_KEY"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
[[ -f $REPO_DIR/nginx/proxygh.conf.template ]] || die "cannot find repository templates"
command -v nginx >/dev/null 2>&1 || die "nginx is not installed"
command -v systemctl >/dev/null 2>&1 || die "systemctl is required"

if [[ $SKIP_PACKAGES -eq 0 ]]; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y apache2-utils ca-certificates curl git
fi
command -v htpasswd >/dev/null 2>&1 || die "htpasswd is missing; install apache2-utils"

install -d -m 0755 /etc/nginx/conf.d /etc/nginx/snippets /etc/nginx/sites-available /etc/nginx/sites-enabled
install -d -m 0755 /var/www/proxygh-acme/.well-known/acme-challenge
BACKUP_ROOT=/etc/nginx/proxygh-backups
install -d -m 0700 "$BACKUP_ROOT"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
declare -a WRITTEN=()
declare -a BACKUPS=()
COMMITTED=0

backup_file() {
    local destination=$1 backup=
    if [[ -e $destination || -L $destination ]]; then
        backup="$BACKUP_ROOT/$(basename -- "$destination").proxygh-backup-${STAMP}"
        cp -a -- "$destination" "$backup"
    fi
    WRITTEN+=("$destination")
    BACKUPS+=("$backup")
}

rollback() {
    local index destination backup
    [[ $COMMITTED -eq 0 ]] || return 0
    for ((index=${#WRITTEN[@]}-1; index>=0; index--)); do
        destination=${WRITTEN[$index]}
        backup=${BACKUPS[$index]}
        rm -f -- "$destination"
        if [[ -n $backup ]]; then
            mv -- "$backup" "$destination"
        fi
    done
}
trap rollback EXIT

ZONES_DEST=/etc/nginx/conf.d/proxygh-zones.conf
COMMON_DEST=/etc/nginx/snippets/proxygh-common.conf
SITE_DEST=/etc/nginx/sites-available/proxygh.conf
SITE_LINK=/etc/nginx/sites-enabled/proxygh.conf

backup_file "$ZONES_DEST"
install -m 0644 "$REPO_DIR/nginx/proxygh-zones.conf" "$ZONES_DEST"

backup_file "$COMMON_DEST"
install -m 0644 "$REPO_DIR/nginx/proxygh-common.conf" "$COMMON_DEST"

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[&|\]/\\&/g'
}
DOMAIN_ESCAPED=$(escape_sed_replacement "$DOMAIN")
CERTIFICATE_ESCAPED=$(escape_sed_replacement "$CERTIFICATE")
CERTIFICATE_KEY_ESCAPED=$(escape_sed_replacement "$CERTIFICATE_KEY")

backup_file "$SITE_DEST"
sed -e "s|__PROXYGH_DOMAIN__|$DOMAIN_ESCAPED|g" \
    -e "s|__PROXYGH_CERTIFICATE__|$CERTIFICATE_ESCAPED|g" \
    -e "s|__PROXYGH_CERTIFICATE_KEY__|$CERTIFICATE_KEY_ESCAPED|g" \
    "$REPO_DIR/nginx/proxygh.conf.template" >"$SITE_DEST"
chmod 0644 "$SITE_DEST"
if grep -q '__PROXYGH_' "$SITE_DEST"; then
    die "unrendered template token found in $SITE_DEST"
fi

backup_file "$SITE_LINK"
ln -sfn "$SITE_DEST" "$SITE_LINK"

if [[ ! -e /etc/nginx/proxygh.htpasswd ]]; then
    install -o root -g www-data -m 0640 /dev/null /etc/nginx/proxygh.htpasswd
else
    chown root:www-data /etc/nginx/proxygh.htpasswd
    chmod 0640 /etc/nginx/proxygh.htpasswd
fi

nginx -t
systemctl reload nginx
COMMITTED=1
trap - EXIT

printf 'ProxyGH installed for https://%s\n' "$DOMAIN"
printf 'Next: sudo %s/add-user.sh USERNAME\n' "$SCRIPT_DIR"
