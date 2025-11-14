//
//  converter_main.h
//  ffconverter
//
//  Created by rei8 on 2019/09/06.
//  Copyright © 2019 lithium03. All rights reserved.
//

#ifndef converter_main_h
#define converter_main_h

void *makeconvert_arg(char *name,
                      void *object,
                      double start,
                      double duration,
                      int arib_convert_text,
                      void(*wait_to_start)(void *opaque),
                      void(*set_duration)(void *opaque, double duration),
                      int(*read_packet)(void *opaque, unsigned char *buf, int buf_size),
                      long long(*seek)(void *opaque, long long offset, int whence),
                      void(*cancel)(void *opaque),
                      void(*encode)(void *opaque, double pts, int key, unsigned char **data, int *linesize, int height),
                      void(*encode_sound)(void *opaque, double pts, unsigned char *data, int size, int ch),
                      void(*encode_text)(void *opaque, double pts_s, double pts_e, const char *data, int ass, int ch),
                      void(*finish)(void *opaque),
                      void(*stream_count)(void *opaque, int audios, int main_audio, const char * const audio_language[], int subtitles, int main_subtitle, const char * const subtitle_language[]),
                      void(*stream_select)(void *opaque, int *result, int video_count, const int video_index[], const char * const video_language[], int subtile_count, const int subtile_index[], const char * const subtitle_language[]));
int run_play(void *arg);
int run_finish(void *arg);

int abort_run(void *arg);

#endif /* converter_main_h */
