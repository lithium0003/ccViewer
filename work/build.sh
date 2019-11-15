#!/bin/bash

ios_run="true"
simulator_run="true"
macos_run="true"
combine_run="true"

(
	cd ffmpeg
	patch --forward -r- -p1 <../maccatalyst.patch
)
rm -rf build output ffmpeg.xcframework

export PATH=$PATH:$PWD/gas-preprocessor

if [ -n "$ios_run" ]; then
	mkdir -p output/ios
	OUTPUT=$PWD/output/ios

	mkdir -p build/ios && ( 
		cd build/ios
		FFmpeg=../../ffmpeg
		"$FFmpeg/configure" \
			--cc="$(xcrun --sdk iphoneos -f clang)" \
			--enable-cross-compile --disable-debug --disable-programs --disable-doc \
			--enable-pic \
			--prefix="$OUTPUT" --target-os=darwin --arch=arm64 \
			--sysroot=$(xcrun --sdk iphoneos --show-sdk-path) \
			--extra-cflags='-target arm64-apple-ios12.0 -fembed-bitcode' \
			--extra-ldflags='-target arm64-apple-ios12.0' \
			|| exit 1
		make -j$(getconf _NPROCESSORS_ONLN) install || exit 1
	)
fi

if [ -n "$simulator_run" ]; then
	mkdir -p output/simulator
	OUTPUT=$PWD/output/simulator

	mkdir -p build/simulator && ( 
		cd build/simulator
		FFmpeg=../../ffmpeg
		"$FFmpeg/configure" \
			--enable-cross-compile --disable-debug --disable-programs --disable-doc \
			--enable-pic \
			--disable-asm \
			--prefix="$OUTPUT" --target-os=darwin --arch=x86 \
			--sysroot=$(xcrun --sdk iphonesimulator --show-sdk-path) \
			--extra-cflags='-target x86_64-apple-ios12.0-simulator -fembed-bitcode' \
			--extra-ldflags='-target x86_64-apple-ios12.0-simulator' \
			|| exit 1
		make -j$(getconf _NPROCESSORS_ONLN) install || exit 1
	)
fi

if [ -n "$macos_run" ]; then
	mkdir -p output/macos
	OUTPUT=$PWD/output/macos

	mkdir -p build/macos && ( 
		cd build/macos
		FFmpeg=../../ffmpeg
		"$FFmpeg/configure" \
			--cc="$(xcrun --sdk macosx -f clang)" \
			--enable-cross-compile --disable-debug --disable-programs --disable-doc \
			--enable-pic \
			--disable-asm \
			--disable-securetransport --disable-coreimage \
			--prefix="$OUTPUT" --target-os=darwin --arch=x86 \
			--sysroot=$(xcrun --sdk macosx --show-sdk-path) \
			--extra-cflags='-target x86_64-apple-ios13.0-macabi -fembed-bitcode' \
			--extra-ldflags='-target x86_64-apple-ios13.0-macabi' \
			|| exit 1
		make -j$(getconf _NPROCESSORS_ONLN) install || exit 1
	)
fi

if [ -n "$combine_run" ]; then
	for arch in output/*
	do
		(cd $arch && libtool -static -o ffmpeg.a lib/*.a)
	done
	mkdir -p ffmpeg.xcframework && (
		cd ffmpeg.xcframework

cat >Info.plist <<EOS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
EOS

if [ -d ../output/ios ]; then
	mkdir -p ios-arm64/Headers
	cp -r ../output/ios/include/* ios-arm64/Headers/
	cp ../output/ios/ffmpeg.a ios-arm64/
cat >ios-arm64/Headers/ffmpeg.h <<EOS
#import "libavcodec/avcodec.h"
#import "libavdevice/avdevice.h"
#import "libavfilter/avfilter.h"
#import "libavformat/avformat.h"
#import "libavutil/avutil.h"
#import "libswresample/swresample.h"
#import "libswscale/swscale.h"
EOS

cat >>Info.plist <<EOS
		<dict>
			<key>LibraryIdentifier</key>
			<string>ios-arm64</string>
			<key>LibraryPath</key>
			<string>ffmpeg.a</string>
			<key>HeadersPath</key>
			<string>Headers</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
		</dict>
EOS
fi

if [ -d ../output/simulator ]; then
	mkdir -p ios-x86_64-simulator/Headers
	cp -r ../output/simulator/include/* ios-x86_64-simulator/Headers/
	cp ../output/simulator/ffmpeg.a ios-x86_64-simulator/
cat >ios-x86_64-simulator/Headers/ffmpeg.h <<EOS
#import "libavcodec/avcodec.h"
#import "libavdevice/avdevice.h"
#import "libavfilter/avfilter.h"
#import "libavformat/avformat.h"
#import "libavutil/avutil.h"
#import "libswresample/swresample.h"
#import "libswscale/swscale.h"
EOS

cat >>Info.plist <<EOS
		<dict>
			<key>LibraryIdentifier</key>
			<string>ios-x86_64-simulator</string>
			<key>LibraryPath</key>
			<string>ffmpeg.a</string>
			<key>HeadersPath</key>
			<string>Headers</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>x86_64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
			<key>SupportedPlatformVariant</key>
			<string>simulator</string>
		</dict>
EOS
fi

if [ -d ../output/macos ]; then
	mkdir -p ios-x86_64-maccatalyst/Headers
	cp -r ../output/macos/include/* ios-x86_64-maccatalyst/Headers/
	cp ../output/macos/ffmpeg.a ios-x86_64-maccatalyst/
cat >ios-x86_64-maccatalyst/Headers/ffmpeg.h <<EOS
#import "libavcodec/avcodec.h"
#import "libavdevice/avdevice.h"
#import "libavfilter/avfilter.h"
#import "libavformat/avformat.h"
#import "libavutil/avutil.h"
#import "libswresample/swresample.h"
#import "libswscale/swscale.h"
EOS

cat >>Info.plist <<EOS
		<dict>
			<key>LibraryIdentifier</key>
			<string>ios-x86_64-maccatalyst</string>
			<key>LibraryPath</key>
			<string>ffmpeg.a</string>
			<key>HeadersPath</key>
			<string>Headers</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>x86_64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
			<key>SupportedPlatformVariant</key>
			<string>maccatalyst</string>
		</dict>
EOS
fi

cat >>Info.plist <<EOS
	</array>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
EOS
	
	)
fi
