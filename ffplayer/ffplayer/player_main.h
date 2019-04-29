//
//  player_main.h
//  ffplayer
//
//  Created by rei6 on 2019/03/22.
//  Copyright © 2019 lithium03. All rights reserved.
//

#ifndef player_main_h
#define player_main_h

void *make_arg(int isPhone, double start,
               char *name, char *font_path, int fontsize,
               char *image1,
               char *image2,
               char *image3,
               char *image4,
               double latency,
               void *object,
               int(*read_packet)(void *opaque, unsigned char *buf, int buf_size),
               long long(*seek)(void *opaque, long long offset, int whence),
               void(*cancel)(void *opaque),
               void(*update_info)(void *opaque, int play, double pos, double len));

int sdlInit(void);
int sdlDone(void);

int play_pause(void *arg, int pause);
int play_latency(void *arg, double latency);
int play_seek(void *arg, double position);

int run_play(void *arg);
int run_loop(void *arg);
double run_finish(void *arg);

void set_image(void *arg, void *mem, int len);

void didChangeStatusBarOrientation(void);
void applicationWillTerminate(void);
void applicationWillResignActive(void);
void applicationDidEnterBackground(void);
void applicationWillEnterForeground(void);
void applicationDidBecomeActive(void);

#endif /* player_main_h */
