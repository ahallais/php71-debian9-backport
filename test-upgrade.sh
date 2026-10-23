#!/bin/bash
# Runs inside debian/eol:stretch. /old = Debian 7.1.20-1 debs, /new = rebuilt 7.1.33-80~deb9+1 debs.
set -e
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99v
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends libfcgi0ldbl procps >/dev/null

echo "== 1. install Debian 7.1.20-1 (state of the VMs)"
apt-get install -y -qq --no-install-recommends /old/*.deb >/tmp/old.log 2>&1 || { tail -20 /tmp/old.log; exit 1; }
php-fpm7.1 -v | head -1

# Simulate the hardening already applied on the hosts + a local edit to a conffile
echo "session.upload_progress.enabled = 0" > /etc/php/7.1/fpm/conf.d/99-mitigate-php2shell.ini
sed -i 's/^;*pm\.max_requests\s*=.*/pm.max_requests = 1/' /etc/php/7.1/fpm/pool.d/www.conf

echo "== 2. upgrade in place with the same package set"
cd /new
debs=""; for f in /old/*.deb; do p=$(dpkg-deb -f "$f" Package); debs="$debs $(ls ./${p}_7.1.33-*_amd64.deb)"; done
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::=--force-confold --no-install-recommends $debs >/tmp/new.log 2>&1 || { tail -30 /tmp/new.log; exit 1; }
dpkg -l 'php7.1*' | awk '/^ii/{print $2, $3}'

echo "== 3. config preserved?"
grep -n '^pm.max_requests' /etc/php/7.1/fpm/pool.d/www.conf
cat /etc/php/7.1/fpm/conf.d/99-mitigate-php2shell.ini

echo "== 4. binary checks"
php-fpm7.1 -v | head -1
php-fpm7.1 -t 2>&1 | tail -1
echo -n "libsodium linked into php-fpm: "; ldd /usr/sbin/php-fpm7.1 | grep -c sodium || true
echo -n "telemetry strings in php-fpm: "; grep -a -c 'telemetry' /usr/sbin/php-fpm7.1 || true
php-fpm7.1 -i | grep -E '^session.upload_progress.enabled'
php -m | tr '\n' ' '; echo

echo "== 5. serve a request through FPM"
mkdir -p /run/php /var/www && echo '<?php echo "OK ", PHP_VERSION, "\n";' > /var/www/t.php
php-fpm7.1 -D; sleep 1
SCRIPT_FILENAME=/var/www/t.php REQUEST_METHOD=GET cgi-fcgi -bind -connect /run/php/php7.1-fpm.sock | tail -1
for i in 1 2 3; do SCRIPT_FILENAME=/var/www/t.php REQUEST_METHOD=GET cgi-fcgi -bind -connect /run/php/php7.1-fpm.sock >/dev/null; done
echo "worker PIDs after 4 requests (should keep changing, max_requests=1):"; pgrep -f 'php-fpm: pool' | tr '\n' ' '; echo
