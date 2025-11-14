#!/bin/sh

mkdir -p output
output=$(realpath output)

mkdir -p build/libaribcaption && cd build/libaribcaption
cmake ../../libaribcaption -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX=$output \
	-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0
cmake --build . -j$(getconf _NPROCESSORS_ONLN)
cmake --install .
