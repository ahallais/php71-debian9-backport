# Build php7.1 7.1.33-80 (Sury backport of CVE-2026-109618 / CVE-2026-109619)
# as Debian 9 "stretch" .deb packages.
FROM debian/eol:stretch

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

RUN echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-valid-until \
 && apt-get update \
 && apt-get install -y --no-install-recommends build-essential devscripts equivs quilt fakeroot

COPY sury/build/php7.1-7.1.33 /src/php7.1-7.1.33
COPY sury/php7.1_7.1.33.orig.tar.xz /src/
WORKDIR /src/php7.1-7.1.33

RUN mk-build-deps debian/control \
 && apt-get install -y --no-install-recommends ./php7.1-build-deps_*.deb \
 && rm -f php7.1-build-deps_*

# Local version suffix so it sorts above 7.1.20-1 and is identifiable on the hosts
RUN DEBEMAIL="arnaud.hallais@havas.com" DEBFULLNAME="Arnaud Hallais" \
    dch -b -v 7.1.33-80~deb9+1 -D stretch \
    "Rebuild of Sury 7.1.33-80 for Debian 9 (CVE-2026-109618, CVE-2026-109619); telemetry patch 0177 dropped; php-common dependency relaxed to stretch (1:49)."

RUN DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -us -uc -b > /src/build.log 2>&1 \
 || (tail -80 /src/build.log; exit 1)
