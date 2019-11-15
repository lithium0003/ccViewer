//
//  converter_main.c
//  ffconverter
//
//  Created by rei8 on 2019/09/06.
//  Copyright © 2019 lithium03. All rights reserved.
//

#include "converter_main.h"

#include "libavformat/avformat.h"

#include "converter_param.h"

extern AVPacket flush_pkt;
extern AVPacket eof_pkt;
extern AVPacket abort_pkt;

static const char *FLUSH_STR = "FLUSH";
static const char *EOF_STR = "EOF";
static const char *ABORT_STR = "ABORT";

void *makeconvert_arg(char *name,
                      void *object,
                      double start,
                      double duration,
                      int(*read_packet)(void *opaque, unsigned char *buf, int buf_size),
                      long long(*seek)(void *opaque, long long offset, int whence),
                      void(*cancel)(void *opaque),
                      void(*encode)(void *opaque, double pts, int key, unsigned char *data, int linesize, int height),
                      void(*encode_sound)(void *opaque, double pts, unsigned char *data, int size, int ch),
                      void(*encode_text)(void *opaque, double pts_s, double pts_e, const char *data, int ass, int ch),
                      void(*finish)(void *opaque),
                      void(*stream_count)(void *opaque, int audios, int main_audio, const char * const audio_language[], int subtitles, int main_subtitle, const char * const subtitle_language[]),
                      void(*stream_select)(void *opaque, int *result, int video_count, const int video_index[], const char * const video_language[], int subtile_count, const int subtile_index[], const char * const subtitle_language[]))
{
    struct convert_param *param = (struct convert_param *)av_malloc(sizeof(struct convert_param));
    param->name = name;
    param->stream = object;
    param->start = start;
    param->duration = duration;
    param->read_packet = read_packet;
    param->seek = seek;
    param->cancel = cancel;
    param->encode = encode;
    param->encode_sound = encode_sound;
    param->encode_text = encode_text;
    param->finish = finish;
    param->stream_count = stream_count;
    param->stream_select = stream_select;
    return param;
}

int run_play(void *arg)
{
    struct convert_param *param = (struct convert_param *)arg;
    
    setParam(param);
    
    av_init_packet(&flush_pkt);
    av_packet_from_data(&flush_pkt, (uint8_t *)FLUSH_STR, (int)strlen(FLUSH_STR));
    av_init_packet(&eof_pkt);
    av_packet_from_data(&eof_pkt, (uint8_t *)EOF_STR, (int)strlen(EOF_STR));
    av_init_packet(&abort_pkt);
    av_packet_from_data(&abort_pkt, (uint8_t *)ABORT_STR, (int)strlen(ABORT_STR));
    
    createParseThread(param);
    
    return 0;
}

int run_finish(void *arg)
{
    struct convert_param *param = (struct convert_param *)arg;
    
    int status = waitParseThread(param);
    
    freeParam(param);
    av_freep(&arg);
    
    return status;
}

int abort_run(void *arg)
{
    struct convert_param *param = (struct convert_param *)arg;
    cancelConvert(param);

    return 0;
}
