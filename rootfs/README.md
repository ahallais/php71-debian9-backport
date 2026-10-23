# Rootfs Base Image

The bootstrapped Debian buster (snapshot 2018-08-01) image archive `buster-20180801.tar.gz` (~220 MB) is excluded from version control due to file size limits.

To recreate it:

```bash
docker run --rm --privileged -v $PWD/rootfs:/out debian:bookworm bash -c '
  apt-get update -qq && apt-get install -y -qq debootstrap debian-archive-keyring ca-certificates
  debootstrap --variant=buildd \
    --keyring=/usr/share/keyrings/debian-archive-removed-keys.gpg \
    buster /target https://snapshot.debian.org/archive/debian/20180801T000000Z/ \
    > /out/debootstrap.log 2>&1 || { tail -20 /out/debootstrap.log; exit 1; }
  tar -C /target -c . | gzip -1 > /out/buster-20180801.tar.gz'
```

See [build.md](../build.md) for full details.
