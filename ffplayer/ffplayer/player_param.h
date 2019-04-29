//
//  player_param.h
//  ffplayer
//
//  Created by rei6 on 2019/03/22.
//  Copyright © 2019 lithium03. All rights reserved.
//

#ifndef player_param_h
#define player_param_h

struct stream_param {
    int isPhone;
    double start;
    char *name;
    char *font_name;
    int fontsize;
    char *image1;
    char *image2;
    char *image3;
    char *image4;
    double latency;
    void *stream;
    void *player;
    int(*read_packet)(void *opaque, unsigned char *buf, int buf_size);
    long long(*seek)(void *opaque, long long offset, int whence);
    void(*cancel)(void *opaque);
    void(*update_info)(void *opaque, int play, double pos, double len);
    
    Uint32 messageBase;
    TTF_Font *font;
    SDL_Window *window;
    SDL_Renderer *renderer;
    SDL_Thread *parse_tid;
    int seeking;
};

#ifdef __cplusplus
extern "C" {
#endif /* __cplusplus */

int decode_thread(void *arg);
void setParam(struct stream_param * param);
void freeParam(struct stream_param * param);
    double getPosition(struct stream_param * param);
int eventLoop(struct stream_param * param);

int externalPause(struct stream_param * param, int pause);
int externalLatency(struct stream_param * param, double latency);
int externalSeek(struct stream_param * param, double position);

void setImage(struct stream_param *param, void *mem, int len);
    
#ifdef __cplusplus
}
#endif /* __cplusplus */

    
#define SDL_AUDIO_BUFFER_SIZE 1 * 1024
#define MAX_AUDIO_FRAME_SIZE 192000

#define VIDEO_PICTURE_QUEUE_SIZE 5

#define MAX_AUDIOQ_SIZE (1 * 1024 * 1024)
#define MAX_VIDEOQ_SIZE (16 * 1024 * 1024)

#define AV_SYNC_THRESHOLD 0.01
#define AV_NOSYNC_THRESHOLD 9.0
#define AV_SYNC_FRAMEDUP_THRESHOLD 0.1

#define SAMPLE_CORRECTION_PERCENT_MAX 10
#define AUDIO_DIFF_AVG_NB 20

//#define FF_REFRESH_EVENT          (SDL_USEREVENT)
//#define FF_INTERNAL_REFRESH_EVENT (SDL_USEREVENT + 1)
//#define FF_QUIT_EVENT             (SDL_USEREVENT + 2)
//#define FF_PAUSE_EVENT            (SDL_USEREVENT + 3)

#endif /* player_param_h */
