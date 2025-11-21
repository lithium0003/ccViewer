#!/bin/sh

mkdir -p output
output=$(realpath output)
export PKG_CONFIG_PATH=$output/lib/pkgconfig

mkdir -p build/ffmpeg && cd build/ffmpeg
../../ffmpeg/configure \
	--cc=$(xcrun --sdk iphonesimulator -f clang) \
	--enable-cross-compile --disable-debug --disable-programs --disable-doc \
	--enable-pic \
	--prefix="$output" --target-os=darwin --arch=arm64 \
	--sysroot=$(xcrun --sdk iphonesimulator --show-sdk-path) \
	--disable-audiotoolbox --enable-libaribcaption \
	--extra-cflags="-miphonesimulator-version-min=26.0" \
	--extra-ldflags="-miphonesimulator-version-min=26.0"
make -j$(getconf _NPROCESSORS_ONLN) install
