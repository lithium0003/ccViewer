//
//  converter_param.h
//  ffconverter
//
//  Created by rei8 on 2019/09/06.
//  Copyright © 2019 lithium03. All rights reserved.
//

#ifndef converter_param_h
#define converter_param_h

struct convert_param {
    char *name;
    void *stream;
    void *converter;
    double start;
    double duration;
    int arib_convert_text;
    void(*wait_to_start)(void *opaque);
    void(*set_duration)(void *opaque, double duration);
    int(*read_packet)(void *opaque, unsigned char *buf, int buf_size);
    long long(*seek)(void *opaque, long long offset, int whence);
    void(*cancel)(void *opaque);
    void(*encode)(void *opaque, double pts, int key, unsigned char **data, int *linesize, int height);
    void(*encode_sound)(void *opaque, double pts, unsigned char *data, int size, int ch);
    void(*encode_text)(void *opaque, double pts_s, double pts_e, const char *data, int ass, int ch);
    void(*finish)(void *opaque);
    void(*stream_count)(void *opaque, int audios, int main_audio, const char * const audio_language[], int subtitles, int main_subtitle, const char * const subtitle_language[]);
    void(*stream_select)(void *opaque, int *result, int video_count, const int video_index[], const char * const video_language[], int subtile_count, int const subtile_index[], const char * const subtitle_language[]);
};

#ifdef __cplusplus
extern "C" {
#endif /* __cplusplus */
    
    void setParam(struct convert_param * param);
    void freeParam(struct convert_param * param);
    int createParseThread(struct convert_param * param);
    int waitParseThread(struct convert_param * param);
    int cancelConvert(struct convert_param * param);
    
#ifdef __cplusplus
}
#endif /* __cplusplus */

#define MAX_AUDIOQ_SIZE (512)
#define MAX_VIDEOQ_SIZE (512)

#endif /* converter_param_h */
