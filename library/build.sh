#!/bin/bash

install_dir=$(pwd)/install_ios

(
cd openssl

export CROSS_COMPILE=`xcode-select --print-path`/Toolchains/XcodeDefault.xctoolchain/usr/bin/
export CROSS_TOP=`xcode-select --print-path`/Platforms/iPhoneOS.platform/Developer/
export CROSS_SDK=iPhoneOS.sdk
export __CNF_CFLAGS=-fembed-bitcode

./Configure --prefix=$install_dir -no-tests -no-legacy ios64-cross && make -j && make install_sw
make distclean
)

(
cd libssh

cmake -H. -Bbuild -DCMAKE_INSTALL_PREFIX=$install_dir -DBUILD_STATIC_LIB=ON -DBUILD_SHARED_LIBS=OFF -DWITH_EXAMPLES=OFF -DCMAKE_BUILD_TYPE=Release -GXcode -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_PREFIX_PATH=$install_dir -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH
cmake --build build/ --config Release -- CODE_SIGNING_ALLOWED=NO OTHER_CFLAGS="-fembed-bitcode" ENABLE_BITCODE=YES BITCODE_GENERATION_MODE=bitcode
cmake --install build/
rm -rf build
)


install_dir=$(pwd)/install_simulator

(
cd openssl

export CROSS_TOP=`xcode-select --print-path`/Platforms/iPhoneSimulator.platform/Developer/
export CROSS_SDK=iPhoneSimulator.sdk

./Configure --prefix=$install_dir -no-tests -no-shared -no-legacy iossimulator-xcrun && make -j && make install_sw
make distclean
)

(
cd libssh

OSX_SYSROOT=`xcode-select --print-path`/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk

cmake -H. -Bbuild -DCMAKE_INSTALL_PREFIX=$install_dir -DBUILD_STATIC_LIB=ON -DBUILD_SHARED_LIBS=OFF -DWITH_EXAMPLES=OFF -DCMAKE_BUILD_TYPE=Release -GXcode -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=$OSX_SYSROOT -DCMAKE_OSX_ARCHITECTURES="x86_64" -DCMAKE_PREFIX_PATH=$install_dir -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH
cmake --build build/ --config Release -- CODE_SIGNING_ALLOWED=NO -sdk iphonesimulator
cmake --install build/
rm -rf build
)


rm -rf install
mkdir install

cp -r install_ios/include install/

mkdir install/lib

liblist=(
  libcrypto.a
  libssh.a
  libssl.a
)

for lib in ${liblist[@]}; do
	echo $lib
	lipo -create install_ios/lib/$lib install_simulator/lib/$lib -output install/lib/$lib
done

rm -rf install_ios
rm -rf install_simulator


