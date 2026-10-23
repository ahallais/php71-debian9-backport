#!/bin/bash
# Upgrade the php7.1 packages installed on this host to 7.1.33-80~deb9+1
# (fix for CVE-2026-109618 / CVE-2026-109619). Run from this directory as root.
#   ./upgrade-php71.sh          -> dry run only
#   ./upgrade-php71.sh --apply  -> install + restart php7.1-fpm
set -euo pipefail
cd "$(dirname "$0")"
sha256sum --quiet -c SHA256SUMS

debs=()
for p in $(dpkg-query -W -f '${db:Status-Abbrev} ${Package}\n' 'php7.1*' 'libapache2-mod-php7.1' 'libphp7.1-embed' 2>/dev/null | awk '/^ii/{print $2}'); do
    f=$(ls ./"${p}"_7.1.33-80~deb9+1_*.deb 2>/dev/null || true)
    [ -n "$f" ] || { echo "no rebuilt package for installed $p" >&2; exit 1; }
    debs+=("$f")
done
echo "Will upgrade: ${debs[*]}"

# Dry run: abort (without touching anything) if apt would have to install, upgrade
# or remove anything besides the php7.1 packages above, i.e. a dependency is missing
sim=$(apt-get -s --no-download install "${debs[@]}" 2>&1) || { echo "$sim" >&2; exit 1; }
extra=$(echo "$sim" | awk '/^(Inst|Remv) /{print $1, $2}' | grep -v -E '^Inst (php7\.1|libapache2-mod-php7\.1|libphp7\.1-embed)' || true)
[ -z "$extra" ] || { echo "Aborting, apt would also change:" >&2; echo "$extra" >&2; exit 1; }
[ "${1:-}" = "--apply" ] || { echo "Dry run OK. Re-run with --apply."; exit 0; }

cp -a /etc/php/7.1 "/root/etc-php-7.1.bak.$(date +%F-%H%M)"
# keep local edits of dpkg conffiles (pool.d/www.conf) and ucf-managed php.ini files
UCF_FORCE_CONFFOLD=1 dpkg --force-confold -i "${debs[@]}"
php-fpm7.1 -t
systemctl restart php7.1-fpm
php-fpm7.1 -v | head -1
