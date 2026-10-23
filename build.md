# Building PHP 7.1.33-80~deb9+1 for the Debian 9 VMs

How the packages in `release/php7.1-7.1.33-80-deb9.tar` were built, and how to rebuild them.
The result is a set of `.deb` files that upgrade Debian's `php7.1 7.1.20-1` in place with the
fix for **CVE-2026-109618 / CVE-2026-109619**.

## Approach

| Choice | Why |
|---|---|
| Source: Ondřej Surý's `php7.1 7.1.33-80` source package | Contains `0186-Avoid-state-corruption-via-bailout.patch`, the backport of the official fix by PHP core developers (Arnaud Le Blanc, Ilija Tovilo), plus every earlier 7.1 security backport. |
| Build system: **Debian buster as of 2018-08-01** (snapshot.debian.org), not Debian 9 | The VMs aren't pure stretch. Their `php7.1 7.1.20-1` came from sid in Aug 2018 and pulled in libc6 2.27, libcurl4, libicu60, libncurses6. A stretch build needs `libcurl3`, which conflicts with the installed `libcurl4`. The 2018-08-01 buster snapshot has exactly the VMs' libraries. |
| Drop patch `0177` (DNS telemetry) | Combined with Sury's `php-common.mk` it makes php-fpm and mod_php send the package version to `telemetry.sury.org` (DNS, port 53) at startup. Not wanted on our servers. |
| Relax `php-common (>= 1:81~)` to `(>= 1:49~)` | The VMs have php-common 1:62. The 7.1 maintainer scripts only use `php_invoke` / `phpquery`, which old php-common already provides. The newer `php-fpm-socket-helper` is called with systemd's `-` prefix, so it's optional. |
| Version `7.1.33-80~deb9+1` | Sorts above `7.1.20-1`, so dpkg treats it as an upgrade, and is easy to recognise on the hosts. |

## Requirements

- Linux x86_64 with Docker (tested with Docker 28.5) and internet access
- ~5 GB free disk, about 15 min on 16 cores
- `curl`, `python3`

All commands below run from the project directory:

```bash
mkdir -p ~/oldphp && cd ~/oldphp
```

## 1. Download the Sury source package

```bash
mkdir -p sury && cd sury
curl -fsSL https://packages.sury.org/php/dists/bookworm/main/source/Sources.gz -o Sources-bookworm.gz
zcat Sources-bookworm.gz | awk '/^Package: php7.1$/{p=1} p&&/^Version:/{print} p&&/^$/{p=0}'
# -> Version: 7.1.33-80+0~20261021.127+debian12~1.gbp7a3318

zcat Sources-bookworm.gz \
 | awk '/^Package: php7.1$/{p=1} p&&/^Files:/{f=1;next} p&&f&&/^ /{print $3} p&&f&&!/^ /{f=0} p&&/^$/{p=0}' \
 | while read f; do curl -fsSLO https://packages.sury.org/php/pool/main/p/php7.1/$f; done
sha256sum php7.1_7.1.33*
```

Expected checksums of the files used for the released build:

```
f30726a670d6643fd44b2c795008ae18d00e55d2d10dafbb84e95e395aa83529  php7.1_7.1.33-80+0~20261021.127+debian12~1.gbp7a3318.dsc
f9822787ca4c1f01a14e5520d703f7aac9bfcd5fdd18db946814506e5c4db84c  php7.1_7.1.33-80+0~20261021.127+debian12~1.gbp7a3318.debian.tar.xz
bd7c0a9bd5433289ee01fd440af3715309faf583f75832b64fe169c100d52968  php7.1_7.1.33.orig.tar.xz
```

Sury replaces packages in place. If a newer `7.1.33-NN` is listed, read its
`debian/changelog` and patch list before using it (check again for telemetry or other
unexpected patches). If the old version is gone, the files above are kept in
`~/oldphp/sury/`.

## 2. Prepare the source tree

```bash
mkdir -p build deb
tar -xJf php7.1_*.debian.tar.xz -C deb
tar -xJf php7.1_7.1.33.orig.tar.xz -C build      # -> build/php-7.1.33
mv build/php-7.1.33 build/php7.1-7.1.33
cp -a deb/debian build/php7.1-7.1.33/
cd build/php7.1-7.1.33/debian

# Check that the CVE fix is in the series
grep -n 0186-Avoid-state-corruption-via-bailout patches/series

# a) drop the DNS telemetry patch
sed -i '/^0177-/d' patches/series

# b) don't pull TELEMETRY_* defines from Sury's php-common.mk
sed -i 's|^-include /usr/lib/php/php-common.mk|# telemetry include removed for internal stretch build|' rules

# c) accept the php-common already on the VMs
sed -i 's/php-common (>= 1:81~)/php-common (>= 1:49~)/' control php-module.control.in

cd ~/oldphp
```

## 3. Bootstrap the 2018-08-01 buster base image

`debootstrap` checks the snapshot's Release signature against Debian's archive keys
(`debian-archive-removed-keys.gpg` holds the 2018 stretch signing key):

```bash
mkdir -p rootfs
docker run --rm --privileged -v $PWD/rootfs:/out debian:bookworm bash -c '
  apt-get update -qq && apt-get install -y -qq debootstrap debian-archive-keyring ca-certificates
  debootstrap --variant=buildd \
    --keyring=/usr/share/keyrings/debian-archive-removed-keys.gpg \
    buster /target https://snapshot.debian.org/archive/debian/20180801T000000Z/ \
    > /out/debootstrap.log 2>&1 || { tail -20 /out/debootstrap.log; exit 1; }
  tar -C /target -c . | gzip -1 > /out/buster-20180801.tar.gz'
grep "Valid Release signature" rootfs/debootstrap.log
```

Why this snapshot date: its versions match the target Debian 9 VM:

| Package | VM | snapshot 2018-08-01 |
|---|---|---|
| libc6 | 2.27-5 | 2.27-5 |
| libcurl4 | 7.60.0-2 | 7.60.0-2 |
| libicu60 | 60.2-6 | 60.2-6 |
| libgd3 | 2.2.5-4 | 2.2.5-4 |
| libncurses6 | 6.1+20180714-1 | 6.1+20180714-1 |
| libzip4 | 1.1.2-1.1+b1 | 1.1.2-1.1+b1 |
| libssl1.1 | 1.1.0h (Sury) | 1.1.0h-4 |

To target VMs with a different library set, compare against
`https://snapshot.debian.org/archive/debian/<DATE>/dists/buster/main/binary-amd64/Packages.xz`
and pick another date. **The build's libc6 must not be newer than the VM's.**

## 4. Build the packages

Files used: `Dockerfile.buster2018` and `.dockerignore` (both in `~/oldphp`).

`.dockerignore`:

```
sury/build/php7.1-7.1.33/.pc
out
old
snap
sury/deb
sury/defaults
rootfs/debootstrap.log
```

`Dockerfile.buster2018`:

```dockerfile
FROM scratch
ADD rootfs/buster-20180801.tar.gz /

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

RUN echo 'deb https://snapshot.debian.org/archive/debian/20180801T000000Z/ buster main' > /etc/apt/sources.list \
 && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-valid-until \
 && echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/99retries \
 && apt-get update \
 && apt-get install -y --no-install-recommends devscripts equivs quilt fakeroot

COPY sury/build/php7.1-7.1.33 /src/php7.1-7.1.33
COPY sury/php7.1_7.1.33.orig.tar.xz /src/
WORKDIR /src/php7.1-7.1.33

RUN mk-build-deps debian/control \
 && apt-get install -y --no-install-recommends ./php7.1-build-deps_*.deb \
 && rm -f php7.1-build-deps_*

RUN DEBEMAIL="arnaud.hallais@havas.com" DEBFULLNAME="Arnaud Hallais" \
    dch -b -v 7.1.33-80~deb9+1 -D stretch \
    "Rebuild of Sury 7.1.33-80 against buster@2018-08-01 libs for mixed stretch hosts (CVE-2026-109618, CVE-2026-109619); telemetry patch 0177 dropped; php-common dependency relaxed (1:49)."

RUN DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -us -uc -b > /src/build.log 2>&1 \
 || (tail -80 /src/build.log; exit 1)
```

Note: `apt-get update` prints an `EXPKEYSIG` warning, because the 2018 signing key has expired
since. apt then keeps the package indexes that debootstrap already verified in step 3, which is
what we want.

Build and extract:

```bash
docker build -f Dockerfile.buster2018 -t php71-buster2018-build . > build-docker.log 2>&1 \
  || tail -40 build-docker.log
mkdir -p out
docker run --rm -v $PWD/out:/out php71-buster2018-build sh -c 'cp /src/*.deb /src/build.log /out/'
grep "applying 0186" out/build.log      # the CVE patch was applied
ls out/*.deb | wc -l                    # 77 (with -dbgsym packages)
```

## 5. Check the result

Dependencies must be satisfiable on the VMs:

```bash
for p in common fpm curl intl gd zip pgsql readline mcrypt; do
  echo "$p: $(dpkg-deb -f out/php7.1-${p}_7.1.33-*_amd64.deb Depends)"
done
# expect: libc6 (>= 2.27) at most, libcurl4, libicu60, libssl1.1 (>= 1.1.0), php-common (>= 1:49~)
```

No telemetry in the binary:

```bash
docker run --rm -v $PWD/out:/d:ro php71-buster2018-build bash -c \
  'dpkg-deb -x /d/php7.1-fpm_*.deb /x && grep -a -c telemetry /x/usr/sbin/php-fpm7.1'   # 0
```

Upgrade test on a copy of a VM: get Debian's `7.1.20-1` debs from snapshot.debian.org into
`old/` (command in `install.md`, "Rollback"), then:

```bash
zcat rootfs/buster-20180801.tar.gz | docker import - buster2018-base
docker run --rm -v $PWD/old:/old:ro -v $PWD/out:/new:ro -v $PWD/test-upgrade.sh:/t.sh:ro \
  buster2018-base bash /t.sh
```

`test-upgrade.sh` installs 7.1.20-1, applies the mitigation edits, upgrades to the new
packages, then checks that config edits survived, that the FPM config test passes and that
the binary contains no telemetry.

Regression tests (optional, ~5 min): `run-phpt.sh` runs PHP's Zend, session, basic, lang and
`ext/standard/general_functions` tests with the old and the new CLI. Results for the released
build:

- Only `tests/lang/bug45392.phpt` fails on the new build alone. It's expected: out-of-memory
  is now a hard worker exit (see `install.md`).
- 4 old memory-safety bug tests fail on 7.1.20 and pass on the new build.
- The `getservby*` failures come from the container lacking `/etc/services`.

## 6. Package the release

```bash
rm -rf release && mkdir -p release/php7.1-7.1.33-80-deb9
cp out/*.deb release/php7.1-7.1.33-80-deb9/
rm -f release/php7.1-7.1.33-80-deb9/*-dbgsym_*
cp upgrade-php71.sh install.md release/php7.1-7.1.33-80-deb9/   # keep master copies outside release/
(cd release/php7.1-7.1.33-80-deb9 && sha256sum *.deb > SHA256SUMS)
(cd release && tar -cf php7.1-7.1.33-80-deb9.tar php7.1-7.1.33-80-deb9 && sha256sum php7.1-7.1.33-80-deb9.tar)
```

## Files in `~/oldphp`

| Path | Purpose |
|---|---|
| `Dockerfile.buster2018` | the build (used for the release) |
| `Dockerfile` | first attempt, pure stretch: **not usable** on the VMs (libcurl3 vs libcurl4) |
| `rootfs/buster-20180801.tar.gz` | bootstrapped 2018 buster base |
| `sury/` | downloaded Sury source + patched tree in `sury/build/php7.1-7.1.33` |
| `out/` | build output (all .debs incl. dbgsym, `build.log`) |
| `old/` | Debian 7.1.20-1 debs used for upgrade tests |
| `test-upgrade.sh`, `test-fresh.sh`, `fcgi-get.php`, `run-phpt.sh` | test helpers |
| `release/` | what gets shipped to the VMs |
