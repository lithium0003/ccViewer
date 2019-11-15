//
//  player_main.h
//  fftest
//
//  Created by rei8 on 2019/10/18.
//  Copyright © 2019 lithium03. All rights reserved.
//

#ifndef player_main_h
#define player_main_h

void *make_arg(char *name,
               double latency,
               double start_skip,
               double play_duration,
               int media_count,
               void *object,
               int(*read_packet)(void *opaque, unsigned char *buf, int buf_size),
               long long(*seek)(void *opaque, long long offset, int whence),
               void(*cancel)(void *opaque),
               int(*get_width)(void *opaque),
               int(*get_height)(void *opaque),
               void(*draw_pict)(void *opaque, unsigned char *image, int width, int height, int linesize, double t),
               void(*set_duration)(void *opaque, double duration),
               void(*set_soundonly)(void *opaque),
               int(*sound_play)(void *opaque),
               int(*sound_stop)(void *opaque),
               void(*wait_stop)(void *opaque),
               void(*wait_start)(void *opaque),
               void(*cc_draw)(void *opaque, const char *buffer, int type),
               void(*change_lang)(void *opaque, const char *buffer, int type, int idx));

int run_play(void *arg);
int run_finish(void *arg);
int run_quit(void *arg);

int run_seek(void *arg, long long pos);
int run_seek_chapter(void *arg, int inc);
int run_cycle_ch(void *arg, int type);
int run_pause(void *arg, int state);
int get_pause(void *arg);
int set_latency(void *arg, double latency);

double load_sound(void *arg, float *buffer, int num_packets);

#endif /* player_main_h */
