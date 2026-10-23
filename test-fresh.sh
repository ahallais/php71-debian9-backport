#!/bin/bash
# Runs inside debian/eol:stretch. /new = rebuilt 7.1.33-80~deb9+1 debs.
set -e
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99v
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends libfcgi0ldbl procps >/dev/null

echo "== 1. install 7.1.33-80~deb9+1 on pure stretch"
cd /new
pkgs="fpm cli common json opcache readline mysql mbstring xml curl gd intl zip"
debs=""; for p in $pkgs; do debs="$debs $(ls ./php7.1-${p}_7.1.33-*_amd64.deb)"; done
apt-get install -y -qq --no-install-recommends $debs >/tmp/new.log 2>&1 || { tail -30 /tmp/new.log; exit 1; }
dpkg -l 'php7.1*' | awk '/^ii/{print $2, $3}'

echo "session.upload_progress.enabled = 0" > /etc/php/7.1/fpm/conf.d/99-mitigate-php2shell.ini
sed -i 's/^;*pm\.max_requests\s*=.*/pm.max_requests = 1/' /etc/php/7.1/fpm/pool.d/www.conf

echo "== 2. binary checks"
php-fpm7.1 -v | head -1
php-fpm7.1 -t 2>&1 | tail -1
echo -n "libsodium linked into php-fpm: "; ldd /usr/sbin/php-fpm7.1 | grep -c sodium || true
echo -n "telemetry strings in php-fpm: "; grep -a -c 'telemetry' /usr/sbin/php-fpm7.1 || true
echo -n "max glibc symbol required: "; objdump -T /usr/sbin/php-fpm7.1 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1 || true
php-fpm7.1 -i | grep -E '^session.upload_progress.enabled'
php -m | tr '\n' ' '; echo

echo "== 3. serve requests through FPM"
mkdir -p /run/php /var/www && echo '<?php echo "OK ", PHP_VERSION, " pid=", getmypid(), "\n";' > /var/www/t.php
php-fpm7.1 -D; sleep 1
for i in 1 2 3; do SCRIPT_FILENAME=/var/www/t.php REQUEST_METHOD=GET cgi-fcgi -bind -connect /run/php/php7.1-fpm.sock | tail -1; done
