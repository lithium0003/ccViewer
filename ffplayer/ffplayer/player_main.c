//
//  player_main.c
//  fftest
//
//  Created by rei8 on 2019/10/18.
//  Copyright © 2019 lithium03. All rights reserved.
//

#include "player_main.h"
#include "player_param.h"

#include <string.h>
#include <libavutil/avutil.h>
#include <libavcodec/avcodec.h>

void *make_arg(char *name,
               double latency,
               double partial_start,
               double start_skip,
               double play_duration,
               int arib_convert_text,
               void *object,
               int(*read_packet)(void *opaque, unsigned char *buf, int buf_size),
               long long(*seek)(void *opaque, long long offset, int whence),
               void(*cancel)(void *opaque),
               void(*draw_pict)(void *opaque, unsigned char **images, int width, int height, int *linesizes, double t),
               void(*set_duration)(void *opaque, double duration),
               void(*set_soundonly)(void *opaque, int value),
               int(*sound_play)(void *opaque),
               int(*sound_stop)(void *opaque),
               void(*wait_stop)(void *opaque),
               void(*wait_start)(void *opaque),
               void(*send_pause)(void *opaque, int value),
               void(*skip_media)(void *opaque, int value),
               void(*cc_draw)(void *opaque, const char *buffer, int type),
               void(*change_lang)(void *opaque, const char *buffer, int type, int idx))
{
    struct stream_param *param = (struct stream_param *)av_malloc(sizeof(struct stream_param));
    param->name = name;
    param->latency = latency;
    param->partial_start = partial_start;
    param->start_skip = start_skip;
    param->play_duration = play_duration;
    param->arib_convert_text = arib_convert_text;
    param->stream = object;
    param->read_packet = read_packet;
    param->seek = seek;
    param->cancel = cancel;
    param->draw_pict = draw_pict;
    param->set_duration = set_duration;
    param->set_soundonly = set_soundonly;
    param->sound_play = sound_play;
    param->sound_stop = sound_stop;
    param->wait_stop = wait_stop;
    param->wait_start = wait_start;
    param->send_pause = send_pause;
    param->skip_media = skip_media;
    param->cc_draw = cc_draw;
    param->change_lang = change_lang;
    return param;
}

extern AVPacket flush_pkt;
extern AVPacket eof_pkt;
extern AVPacket abort_pkt;

const char *FLUSH_STR = "FLUSH";
const char *EOF_STR = "EOF";
const char *ABORT_STR = "ABORT";

int run_play(void *arg)
{
    struct stream_param *param = (struct stream_param *)arg;
    
    setParam(param);

    av_packet_from_data(&flush_pkt, (uint8_t *)FLUSH_STR, (int)strlen(FLUSH_STR));
    av_packet_from_data(&eof_pkt, (uint8_t *)EOF_STR, (int)strlen(EOF_STR));
    av_packet_from_data(&abort_pkt, (uint8_t *)ABORT_STR, (int)strlen(ABORT_STR));
    
    createParseThread(param);

    return 0;
}

int run_finish(void *arg)
{
    struct stream_param *param = (struct stream_param *)arg;
    
    int status = waitParseThread(param);
    
    freeParam(param);
    av_freep(&arg);

    return status;
}

int run_quit(void *arg)
{
    struct stream_param *param = (struct stream_param *)arg;
    quitPlayer(param);
    return 0;
}

int run_seek(void *arg, long long pos)
{
    struct stream_param *param = (struct stream_param *)arg;
    seekPlayer(param, pos);
    return 0;
}

int run_seek_chapter(void *arg, int inc)
{
    struct stream_param *param = (struct stream_param *)arg;
    seekPlayerChapter(param, inc);
    return 0;
}

int run_cycle_ch(void *arg, int type)
{
    struct stream_param *param = (struct stream_param *)arg;
    cycleChancelPlayer(param, type);
    return 0;
}

int run_pause(void *arg, int state)
{
    struct stream_param *param = (struct stream_param *)arg;
    pausePlayer(param, state);
    return 0;
}

int set_latency(void *arg, double latency)
{
    struct stream_param *param = (struct stream_param *)arg;
    param->latency = latency;
    return 0;
}
