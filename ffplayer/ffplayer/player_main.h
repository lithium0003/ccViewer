//
//  player_main.h
//  fftest
//
//  Created by rei8 on 2019/10/18.
//  Copyright © 2019 lithium03. All rights reserved.
//

#ifndef player_main_h
#define player_main_h

extern int averror_eof;
extern int averror_exit;

void *make_arg(char *name,
               char *paletteStr,
               double latency,
               double partial_start,
               double start_skip,
               double play_duration,
               double playback_rate,
               int arib_convert_text,
               void *object,
               int(*read_packet)(void *opaque, unsigned char *buf, int buf_size),
               long long(*seek)(void *opaque, long long offset, int whence),
               void(*cancel)(void *opaque),
               void(*draw_pict)(void *opaque, unsigned char **images, int width, int height, int *linesize, double t),
               double(*set_duration)(void *opaque, double duration),
               void(*set_soundonly)(void *opaque, int value),
               int(*sound_play)(void *opaque),
               int(*sound_stop)(void *opaque),
               void(*wait_stop)(void *opaque),
               void(*wait_start)(void *opaque),
               void(*send_pause)(void *opaque, int value),
               void(*skip_media)(void *opaque, int value),
               void(*initial_skip)(void *opaque, double value),
               void(*cc_draw)(void *opaque, const char *buffer, int type),
               void(*change_lang)(void *opaque, const char *buffer, int type, int idx));

int run_play(void *arg);
int run_finish(void *arg);
int run_quit(void *arg);

int run_seek(void *arg, long long pos, long long bytepos);
int run_seek_chapter(void *arg, int inc);
int run_cycle_ch(void *arg, int type);
int run_set_playback_rate(void *arg, double rate);
int run_pause(void *arg, int state);
int set_latency(void *arg, double latency);

double load_sound(void *arg, float *buffer, int num_packets);

#endif /* player_main_h */
