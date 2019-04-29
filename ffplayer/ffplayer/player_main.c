//
//  player_main.c
//  ffplayer
//
//  Created by rei6 on 2019/03/22.
//  Copyright © 2019 lithium03. All rights reserved.
//

#include "player_main.h"

#include <SDL.h>
#include <SDL_thread.h>
#include <SDL_ttf.h>
#include <libavformat/avformat.h>

#include "player_param.h"

extern void SDL_OnApplicationDidChangeStatusBarOrientation(void);
extern void SDL_OnApplicationWillTerminate(void);
extern void SDL_OnApplicationWillResignActive(void);
extern void SDL_OnApplicationDidEnterBackground(void);
extern void SDL_OnApplicationWillEnterForeground(void);
extern void SDL_OnApplicationDidBecomeActive(void);

void didChangeStatusBarOrientation(void)
{
    if (SDL_WasInit(SDL_INIT_EVERYTHING) & SDL_INIT_VIDEO) {
        SDL_OnApplicationDidChangeStatusBarOrientation();
    }
}

void applicationWillTerminate(void)
{
    if (SDL_WasInit(SDL_INIT_EVERYTHING) & SDL_INIT_EVENTS) {
        SDL_OnApplicationWillTerminate();
    }
}

void applicationWillResignActive(void)
{
    if (SDL_WasInit(SDL_INIT_EVERYTHING) & SDL_INIT_EVENTS) {
        SDL_OnApplicationWillResignActive();
    }
}

void applicationDidEnterBackground(void)
{
    if (SDL_WasInit(SDL_INIT_EVERYTHING) & SDL_INIT_EVENTS) {
        SDL_OnApplicationDidEnterBackground();
    }
}

void applicationWillEnterForeground(void)
{
    if (SDL_WasInit(SDL_INIT_EVERYTHING) & SDL_INIT_EVENTS) {
        SDL_OnApplicationWillEnterForeground();
    }
}

void applicationDidBecomeActive(void)
{
    if (SDL_WasInit(SDL_INIT_EVERYTHING) & SDL_INIT_EVENTS) {
        SDL_OnApplicationDidBecomeActive();
    }
}

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
               void(*update_info)(void *opaque, int play, double pos, double len))
{
    struct stream_param *param = (struct stream_param *)av_malloc(sizeof(struct stream_param));
    param->isPhone = isPhone;
    param->start = start;
    param->name = name;
    param->font_name = font_path;
    param->fontsize = fontsize;
    param->image1 = image1;
    param->image2 = image2;
    param->image3 = image3;
    param->image4 = image4;
    param->latency = latency;
    param->stream = object;
    param->read_packet = read_packet;
    param->seek = seek;
    param->cancel = cancel;
    param->update_info = update_info;
    return param;
}

extern AVPacket flush_pkt;
extern AVPacket eof_pkt;
extern AVPacket abort_pkt;

static const char *FLUSH_STR = "FLUSH";
static const char *EOF_STR = "EOF";
static const char *ABORT_STR = "ABORT";

int sdlInit(void)
{
    /* initialize SDL */
    SDL_SetMainReady();
    if (SDL_Init(SDL_INIT_TIMER | SDL_INIT_AUDIO | SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
        printf("SDL: Init failed - exiting\n");
        return 1;
    }
    if (TTF_Init() < 0) {
        printf("TTF_Init() failed - %s\n", TTF_GetError());
        SDL_Quit();
        return 1;
    }
    SDL_SetHint(SDL_HINT_AUDIO_CATEGORY, "playback");
    return 0;
}

int sdlDone(void)
{
    /* shutdown SDL */
    TTF_Quit();
    SDL_Quit();
    return 0;
}

int play_pause(void *arg, int pause)
{
    struct stream_param *param = (struct stream_param *)arg;
    return externalPause(param, pause);
}

int play_latency(void *arg, double latency)
{
    struct stream_param *param = (struct stream_param *)arg;
    return externalLatency(param, latency);
}

int play_seek(void *arg, double position)
{
    struct stream_param *param = (struct stream_param *)arg;
    return externalSeek(param, position);
}

int run_play(void *arg)
{
    struct stream_param *param = (struct stream_param *)arg;
    
    if((param->messageBase = SDL_RegisterEvents(4)) ==  ((Uint32)-1)) {
        return 1;
    }
    
    param->font = TTF_OpenFont(param->font_name, param->fontsize);
    if (param->font == NULL) {
        printf("TTF_OpenFont failed - %s\n", TTF_GetError());
        TTF_Quit();
        SDL_Quit();
        av_freep(&arg);
        return 1;
    }
    param->window = SDL_CreateWindow(NULL, 0, 0, 0, 0, SDL_WINDOW_FULLSCREEN | SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_OPENGL);
    if (!param->window) {
        printf("SDL_CreateWindow() failed\n");
        TTF_CloseFont(param->font);
        TTF_Quit();
        SDL_Quit();
        av_freep(&arg);
        return 1;
    }
    param->renderer = SDL_CreateRenderer(param->window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_TARGETTEXTURE);
    if (!param->renderer) {
        printf("SDL_CreateRenderer() failed\n");
        SDL_DestroyWindow(param->window);
        TTF_CloseFont(param->font);
        TTF_Quit();
        SDL_Quit();
        av_freep(&arg);
        return 1;
    }
    
    SDL_RenderClear(param->renderer);

    SDL_RenderPresent(param->renderer);
    setParam(param);
    eventLoop(param);
    
    av_init_packet(&flush_pkt);
    av_packet_from_data(&flush_pkt, (uint8_t *)FLUSH_STR, (int)strlen(FLUSH_STR));
    av_init_packet(&eof_pkt);
    av_packet_from_data(&eof_pkt, (uint8_t *)EOF_STR, (int)strlen(EOF_STR));
    av_init_packet(&abort_pkt);
    av_packet_from_data(&abort_pkt, (uint8_t *)ABORT_STR, (int)strlen(ABORT_STR));
    
    param->parse_tid = SDL_CreateThread(decode_thread, "decode", arg);

    return 0;
}

int run_loop(void *arg)
{
    struct stream_param *param = (struct stream_param *)arg;
    return eventLoop(param);
}

double run_finish(void *arg)
{
    struct stream_param *param = (struct stream_param *)arg;

    int status;
    SDL_WaitThread(param->parse_tid, &status);
    
    double pos = getPosition(param);
    freeParam(param);
    SDL_DestroyRenderer(param->renderer);
    SDL_DestroyWindow(param->window);
    TTF_CloseFont(param->font);
    av_freep(&arg);
    
    return (status < 0) ? -1 : pos;
}

void set_image(void *arg, void *mem, int len)
{
    struct stream_param *param = (struct stream_param *)arg;
    setImage(param, mem, len);
}
