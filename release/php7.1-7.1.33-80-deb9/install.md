# Installing PHP 7.1.33-80~deb9+1 (CVE-2026-109618 / CVE-2026-109619 fix)

These packages replace Debian's `php7.1 7.1.20-1` on our Debian 9 VMs with a build that
contains the fix for **CVE-2026-109618 / CVE-2026-109619** ("PHP2Shell", GHSA-w8hw-w9fx-j79w,
GHSA-6wmf-4rv5-p3rp). They upgrade in place: same package names, same paths, same config
files, same extension API (`20160303`).

## Who this is for

VMs that run `php7.1-fpm 7.1.20-1` on "Debian 9", which in practice also have buster/sid
libraries from 2018:

| Library    | Expected on the VM     |
|------------|------------------------|
| libc6      | 2.27-x                 |
| libcurl4   | 7.60.0-x               |
| libicu60   | 60.2-x                 |
| libssl1.1  | 1.1.0h or newer        |
| php-common | 1:49 or newer          |

Check a VM with:

```bash
dpkg -l libc6 libcurl4 libicu60 libssl1.1 php-common 'php7.1*' | awk '/^ii/{print $2, $3}'
```

If the VM is a different setup (pure stretch with libc6 2.24, a php7.0 host, etc.) the dry
run below refuses to install. Don't force it; ask for a matching build.

## Contents of the bundle

```
php7.1-7.1.33-80-deb9/
  *.deb               all php7.1 packages (fpm, cli, common, curl, gd, intl, pgsql, zip, ...)
  SHA256SUMS          checksums of the .deb files
  upgrade-php71.sh    install script
  install.md          this file
```

## 1. Copy the bundle to the VM

```bash
scp php7.1-7.1.33-80-deb9.tar user@target-vm:/tmp/
ssh user@target-vm
cd /tmp && tar xf php7.1-7.1.33-80-deb9.tar && cd php7.1-7.1.33-80-deb9
```

## 2. Dry run (changes nothing)

```bash
sudo ./upgrade-php71.sh
```

The script:

1. Checks every `.deb` against `SHA256SUMS`.
2. Picks only the `php7.1-*` packages already installed on this VM.
3. Simulates the install with apt. It **aborts** if apt would also need to install, upgrade
   or remove any other package (meaning a library is missing on this VM).

Expected end of output: `Dry run OK. Re-run with --apply.`

## 3. Install

Pick a quiet moment. php-fpm restarts, so in-flight requests are dropped.

```bash
sudo ./upgrade-php71.sh --apply
```

What it does:

1. Backs up `/etc/php/7.1` to `/root/etc-php-7.1.bak.<date>`.
2. Installs the packages and **keeps your local config edits** (`pool.d/www.conf`, `php.ini`,
   `conf.d/*`).
3. Runs `php-fpm7.1 -t` (configuration test).
4. Restarts `php7.1-fpm` and prints the new version.

## 4. Verify

```bash
php-fpm7.1 -v | head -1                 # PHP 7.1.33-80~deb9+1 (fpm-fcgi)
systemctl status php7.1-fpm --no-pager  # active (running)
dpkg -l 'php7.1*' | awk '/^ii/{print $2, $3}'   # all 7.1.33-80~deb9+1
```

Then load the application through nginx and check `/var/log/php7.1-fpm.log` and the nginx
error log.

## 5. After the upgrade: temporary mitigations

- `pm.max_requests = 1` in `/etc/php/7.1/fpm/pool.d/www.conf` is no longer needed. Set it
  back to e.g. `500` to recover performance, then `sudo systemctl restart php7.1-fpm`.
- **Keep** `session.upload_progress.enabled = 0`
  (`/etc/php/7.1/fpm/conf.d/99-mitigate-php2shell.ini`) unless the application needs
  upload progress. The advisory recommends this even after patching.

## Behaviour change to know about

When a script exceeds `memory_limit` ("Allowed memory size ... exhausted"), the patched PHP
**kills the worker immediately** instead of running the normal error handling. This is
intended: it is how the fix removes out-of-memory as an attack path.

- nginx returns **502** for that request instead of 500.
- Shutdown functions and destructors don't run for that request.
- The message no longer appears in PHP's `error_log`. The FPM log shows
  `child NNNN exited with code 1`. Look for that line when investigating 502s.

Other fatal errors (uncaught exceptions, undefined functions, ...) behave as before.

## Rollback

The old `7.1.20-1` packages are no longer in any repository, so fetch them first (keep a
copy before upgrading if you can). From a machine with internet access:

```bash
for p in php7.1-cli php7.1-common php7.1-curl php7.1-fpm php7.1-gd php7.1-intl php7.1-json \
         php7.1-mcrypt php7.1-opcache php7.1-pgsql php7.1-readline php7.1-xml php7.1-zip; do
  h=$(curl -fsS "https://snapshot.debian.org/mr/binary/$p/7.1.20-1/binfiles?fileinfo=1" \
      | python3 -c 'import sys,json;print([r["hash"] for r in json.load(sys.stdin)["result"] if r["architecture"]=="amd64"][0])')
  curl -fsSL -o ${p}_7.1.20-1_amd64.deb https://snapshot.debian.org/file/$h
done
```

Then on the VM:

```bash
sudo dpkg --force-confold -i ./*_7.1.20-1_amd64.deb   # downgrade (dpkg warns, that's expected)
sudo cp -a /root/etc-php-7.1.bak.<date>/. /etc/php/7.1/  # if config needs restoring
sudo systemctl restart php7.1-fpm
```

Rolling back reopens the vulnerability. Put the temporary mitigations back
(`pm.max_requests = 1`, `session.upload_progress.enabled = 0`).
