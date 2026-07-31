#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
validate_username() {
    [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] || die "invalid username"
}

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "run this command as root"
[[ $# -eq 1 ]] || die "usage: sudo ./scripts/add-user.sh USERNAME"
command -v htpasswd >/dev/null 2>&1 || die "htpasswd is missing; install apache2-utils"

USERNAME=$1
PASSWORD_FILE=/etc/nginx/proxygh.htpasswd
validate_username "$USERNAME"

if [[ -s $PASSWORD_FILE ]]; then
    htpasswd -B "$PASSWORD_FILE" "$USERNAME"
else
    htpasswd -cB "$PASSWORD_FILE" "$USERNAME"
fi
chown root:www-data "$PASSWORD_FILE"
chmod 640 "$PASSWORD_FILE"
printf 'ProxyGH user %s is ready.\n' "$USERNAME"
