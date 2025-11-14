#!/bin/bash

rm -rf build output
bash build_libaribcaption.sh
bash build_ffmpeg.sh
	
libtool -static -o output/ffmpeg.a output/lib/*.a
