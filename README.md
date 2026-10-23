# php71-debian9-backport

[![Debian 9 Stretch](https://img.shields.io/badge/Debian-9%20Stretch%20%2F%20Buster%202018-A81D33?logo=debian&logoColor=white)](#)
[![PHP Version](https://img.shields.io/badge/PHP-7.1.33--80~deb9%2B1-777BB4?logo=php&logoColor=white)](#)
[![Vulnerability Fix](https://img.shields.io/badge/Fix-CVE--2026--109618%20%2F%20CVE--2026--109619-critical)](#)
[![Telemetry](https://img.shields.io/badge/Telemetry-Removed-success)](#)

Reproducible Docker build recipes, automated in-place upgrade scripts, and pre-built `.deb` packages backporting PHP 7.1 security patches (**CVE-2026-109618 / CVE-2026-109619**, "PHP2Shell") to legacy **Debian 9 ("stretch")** and mixed Buster 2018 systems.

---

## Overview

Debian Stretch hosts running Debian's legacy `php7.1 7.1.20-1` package are exposed to **CVE-2026-109618 / CVE-2026-109619** ("PHP2Shell", GHSA-w8hw-w9fx-j79w, GHSA-6wmf-4rv5-p3rp - memory state corruption via bailout).

Upstream modern packages from Ondřej Surý's repository cannot be installed directly on these legacy systems because:
1. They target modern Debian (Bookworm/Trixie) and pull in modern glibc and library versions.
2. They depend on `php-common (>= 1:81~)`, whereas Debian 9 environments provide `php-common 1:62`.
3. They include patch `0177`, which sends telemetry queries to `telemetry.sury.org` over DNS (port 53) upon service startup.
4. Pure stretch builds link against `libcurl3`, causing unresolvable package conflicts on systems that already have `libcurl4`.

This project solves this by rebuilding **Ondřej Surý's `php7.1 7.1.33-80`** source packages inside a bootstrapped **Debian snapshot (buster as of 2018-08-01)**, producing clean `7.1.33-80~deb9+1` packages that upgrade Debian's `7.1.20-1` in place without disturbing existing libraries.

---

## Key Modifications

| Feature | Upstream Sury 7.1.33-80 | Rebuilt `7.1.33-80~deb9+1` |
|---|---|---|
| **Security Fix** | Contains patch `0186-Avoid-state-corruption-via-bailout.patch` | **Preserved** (official fix by PHP core developers) |
| **DNS Telemetry** | Patch `0177` enabled (`telemetry.sury.org`) | **Removed** (patch dropped, telemetry compiler defines disabled) |
| **`php-common` Dep** | Strictly requires `php-common (>= 1:81~)` | **Relaxed to `(>= 1:49~)`** (compatible with Debian 9's `1:62`) |
| **Base Libraries** | Linked against Debian 12 (glibc 2.36) | **Linked against Debian Buster 2018-08-01 snapshot** (`libc6 2.27`, `libcurl4 7.60.0`, `libicu60 60.2`, `libssl1.1 1.1.0h`) |
| **Packaging Version** | `7.1.33-80+...` | `7.1.33-80~deb9+1` (sorts above Debian's `7.1.20-1` for in-place upgrade) |

---

## Repository Contents

```
.
├── Dockerfile                  # Reference stretch build (legacy / incompatible with libcurl4)
├── Dockerfile.buster2018       # Production reproducible Docker build (2018-08-01 snapshot)
├── build.md                    # In-depth build instructions and checksum documentation
├── install.md                  # Comprehensive host installation and upgrade documentation
├── upgrade-php71.sh            # In-place host upgrade script (supports dry-run and --apply)
├── test-upgrade.sh             # Integration test: upgrades a mock VM from 7.1.20-1 to 7.1.33-80
├── test-fresh.sh               # Integration test: fresh installation validation
├── run-phpt.sh                 # Upstream PHP test suite runner (PHPT regression tests)
├── fcgi-get.php                # Minimal raw FastCGI client for integration checks
├── rootfs/                     # Base system image workspace (see rootfs/README.md)
├── release/                    # Pre-packaged release archive and .deb packages
│   └── php7.1-7.1.33-80-deb9/  # Built .deb files, SHA256SUMS, and upgrade helper
└── sury/                       # Source package metadata and modified Debian packaging rules
```

---

## Quick Start: Upgrading a Host

### 1. Copy the Release Bundle

Pre-built packages are available in [`release/php7.1-7.1.33-80-deb9.tar`](release/php7.1-7.1.33-80-deb9.tar) or from [GitHub Releases](../../releases):

```bash
scp release/php7.1-7.1.33-80-deb9.tar user@target-vm:/tmp/
ssh user@target-vm
cd /tmp && tar xf php7.1-7.1.33-80-deb9.tar && cd php7.1-7.1.33-80-deb9
```

### 2. Run a Dry Run

Verify SHA256 checksums and simulate package installation without making any system changes:

```bash
sudo ./upgrade-php71.sh
```

The script:
1. Validates every `.deb` package against `SHA256SUMS`.
2. Inspects currently installed `php7.1-*` packages on the host.
3. Simulates the upgrade with `apt-get -s`. If any extraneous packages would be modified, it immediately aborts.

### 3. Apply the Upgrade

```bash
sudo ./upgrade-php71.sh --apply
```

This will:
- Back up `/etc/php/7.1` to `/root/etc-php-7.1.bak.<timestamp>`.
- Install the replacement `.deb` packages while preserving local configuration edits (`pool.d/www.conf`, `php.ini`) via `UCF_FORCE_CONFFOLD=1`.
- Run `php-fpm7.1 -t` to test configuration syntax.
- Restart `php7.1-fpm` and display the new version.

### 4. Verify

```bash
php-fpm7.1 -v | head -1
# Output: PHP 7.1.33-80~deb9+1 (fpm-fcgi)

systemctl status php7.1-fpm --no-pager
dpkg -l 'php7.1*' | awk '/^ii/{print $2, $3}'
```

---

## Critical Behavior Change: OOM Handling

Under the CVE-2026-109618 / CVE-2026-109619 security fix, if a script exhausts `memory_limit` ("Allowed memory size ... exhausted"), the PHP engine **terminates the worker process immediately** instead of continuing error execution.

- This is intentional: it prevents memory state corruption from being weaponized.
- Nginx or Apache will return **HTTP 502 Bad Gateway** for that specific request.
- Worker termination is logged in `/var/log/php7.1-fpm.log` as `child <PID> exited with code 1`.

---

## Building from Source

To reproduce the build from source, follow the instructions in [`build.md`](build.md):

1. **Bootstrap 2018 Buster Base Image**:
   ```bash
   docker run --rm --privileged -v $PWD/rootfs:/out debian:bookworm bash -c '
     apt-get update -qq && apt-get install -y -qq debootstrap debian-archive-keyring ca-certificates
     debootstrap --variant=buildd \
       --keyring=/usr/share/keyrings/debian-archive-removed-keys.gpg \
       buster /target https://snapshot.debian.org/archive/debian/20180801T000000Z/ \
       > /out/debootstrap.log 2>&1
     tar -C /target -c . | gzip -1 > /out/buster-20180801.tar.gz'
   ```

2. **Build Packages**:
   ```bash
   docker build -f Dockerfile.buster2018 -t php71-buster2018-build .
   mkdir -p out
   docker run --rm -v $PWD/out:/out php71-buster2018-build sh -c 'cp /src/*.deb /src/build.log /out/'
   ```

3. **Run Regression & Upgrade Tests**:
   ```bash
   zcat rootfs/buster-20180801.tar.gz | docker import - buster2018-base
   docker run --rm -v $PWD/old:/old:ro -v $PWD/out:/new:ro -v $PWD/test-upgrade.sh:/t.sh:ro \
     buster2018-base bash /t.sh
   ```

See [`build.md`](build.md) for full instructions and checksum verification.

---

## License

The packaging and helper scripts are licensed under the [MIT License](LICENSE) or matching PHP / Debian packaging terms. PHP itself is licensed under the [PHP License](https://www.php.net/license/3_01.txt).
