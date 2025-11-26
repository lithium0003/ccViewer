#!/bin/bash

cd ffmpeg
patch -p1 <../ffmpeg_aribcaption.patch 
patch -p1 <../ffmpeg_mov.patch 
