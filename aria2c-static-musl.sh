#!/bin/bash
set -euo pipefail

ORANGE="\033[38;2;255;165;0m"
LEMON="\033[38;2;255;244;79m"
TAWNY="\033[38;2;204;78;0m"
HELIOTROPE="\033[38;2;223;115;255m"
VIOLET="\033[38;2;143;0;255m"
MINT="\033[38;2;152;255;152m"
AQUA="\033[38;2;18;254;202m"
TOMATO="\033[38;2;255;99;71m"
NC="\033[0m"

ARCH=${ARCH:-x86_64}

## map arch to Alpine minirootfs URL and QEMU binary name
case "${ARCH}" in
  x86_64)
    ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/x86_64/alpine-minirootfs-3.23.3-x86_64.tar.gz"
    QEMU_ARCH=""
    ;;
  x86)
    ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/x86/alpine-minirootfs-3.23.3-x86.tar.gz"
    QEMU_ARCH="i386"
    ;;
  aarch64)
    ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/aarch64/alpine-minirootfs-3.23.3-aarch64.tar.gz"
    QEMU_ARCH="aarch64"
    ;;
  armhf)
    ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/armhf/alpine-minirootfs-3.23.3-armhf.tar.gz"
    QEMU_ARCH="arm"
    ;;
  armv7)
    ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/armv7/alpine-minirootfs-3.23.3-armv7.tar.gz"
    QEMU_ARCH="arm"
    ;;
  *)
    echo "Unknown architecture: ${ARCH}"
    exit 1
    ;;
esac

TARBALL="${ALPINE_URL##*/}"

## unmount bind mounts on exit to avoid leaking mounts on failure
cleanup() {
  sudo umount -lf "pasta/proc" 2>/dev/null || true
  sudo umount -lf "pasta/dev"  2>/dev/null || true
  sudo umount -lf "pasta/sys"  2>/dev/null || true
}
trap cleanup EXIT

echo -e "${AQUA}= install dependencies${NC}"
PKGS=(wget curl binutils)
if [ -n "${QEMU_ARCH}" ]; then
  PKGS+=(qemu-user-static)
fi
sudo apt-get update -qy && sudo apt-get install -y "${PKGS[@]}"

echo -e "${AQUA}= fetching latest aria2 version${NC}"
ARIA2_VERSION=$(curl -fsSL "https://api.github.com/repos/aria2/aria2/releases/latest" \
  | grep '"tag_name"' | sed 's/.*"release-\([^"]*\)".*/\1/') || true
if [ -z "${ARIA2_VERSION}" ]; then
  echo -e "${TAWNY}= GitHub API unavailable, falling back to aria2 1.37.0${NC}"
  ARIA2_VERSION="1.37.0"
fi
echo -e "${MINT}= building aria2 version: ${ARIA2_VERSION}${NC}"

echo -e "${HELIOTROPE}= download alpine rootfs${NC}"
wget -c "${ALPINE_URL}"

echo -e "${MINT}= extract rootfs${NC}"
mkdir -p pasta
tar xf "${TARBALL}" -C pasta/

echo -e "${TOMATO}= copy resolv.conf into the folder${NC}"
cp /etc/resolv.conf ./pasta/etc/

if [ -n "${QEMU_ARCH}" ]; then
  echo -e "${TAWNY}= setup QEMU for cross-arch builds${NC}"
  sudo mkdir -p ./pasta/usr/bin/
  sudo cp "/usr/bin/qemu-${QEMU_ARCH}-static" "./pasta/usr/bin/"
fi

echo -e "${VIOLET}= mount, bind and chroot into dir${NC}"
sudo mount -t proc none ./pasta/proc/
sudo mount --rbind /dev ./pasta/dev/
sudo mount --rbind /sys ./pasta/sys/
sudo chroot ./pasta/ /bin/sh -c "apk update && apk add build-base \
musl-dev \
openssl-dev \
zlib-dev \
libpsl-dev \
libuuid \
curl \
gawk \
libidn2-static \
openssl-libs-static \
zlib-static \
libpsl-static \
flex \
bison \
upx \
autoconf \
automake \
libtool \
pkgconfig \
gnutls \
gnutls-dev \
sqlite \
sqlite-dev \
c-ares \
c-ares-dev \
libssh2 \
libssh2-dev \
libssh2-static \
sqlite-static \
lz4-static \
libgpg-error-dev \
libgpg-error-static \
perl && curl -fsSL -O 'https://github.com/aria2/aria2/releases/download/release-${ARIA2_VERSION}/aria2-${ARIA2_VERSION}.tar.gz' && \
tar xf aria2-${ARIA2_VERSION}.tar.gz && \
cd aria2-${ARIA2_VERSION}/ && \
./configure CC=gcc ARIA2_STATIC=yes --without-gnutls --with-openssl --disable-bittorrent LDFLAGS='-static' CFLAGS='-O3 -Wno-unterminated-string-initialization' && \
make -j\$(nproc) && \
strip src/aria2c && \
upx --ultra-brute src/aria2c"
mkdir -p dist
cp "./pasta/aria2-${ARIA2_VERSION}/src/aria2c" "dist/aria2c-${ARCH}"
tar -C dist -cJf "dist/aria2c-${ARCH}.tar.xz" "aria2c-${ARCH}"
echo -e "${LEMON}= All done! Binary: dist/aria2c-${ARCH} ($(du -sh "dist/aria2c-${ARCH}" | cut -f1))${NC}"