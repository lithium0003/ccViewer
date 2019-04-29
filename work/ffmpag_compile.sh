#!/bin/bash

export FFSRC=$(pwd)/ffmpeg
cd avbuild
bash ./avbuild.sh ios "arm64 x86_64"
