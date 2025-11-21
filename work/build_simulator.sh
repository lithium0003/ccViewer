#!/bin/bash

rm -rf build output
bash build_libaribcaption_simulator.sh
bash build_ffmpeg_simulator.sh
	
libtool -static -o output/ffmpeg.a output/lib/*.a
