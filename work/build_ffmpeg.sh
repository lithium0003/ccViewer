#!/bin/sh

mkdir -p output
output=$(realpath output)
export PKG_CONFIG_PATH=$output/lib/pkgconfig

mkdir -p build/ffmpeg && cd build/ffmpeg
../../ffmpeg/configure \
	--cc="$(xcrun --sdk iphoneos -f clang)" \
	--enable-cross-compile --disable-debug --disable-programs --disable-doc \
	--enable-pic \
	--prefix="$output" --target-os=darwin --arch=arm64 \
	--sysroot=$(xcrun --sdk iphoneos --show-sdk-path) \
	--disable-audiotoolbox --enable-libaribcaption \
	--extra-cflags="-mios-version-min=26.0" \
	--extra-ldflags="-mios-version-min=26.0"
make -j$(getconf _NPROCESSORS_ONLN) install
