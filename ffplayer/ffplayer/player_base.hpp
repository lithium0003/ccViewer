//
//  player_base.hpp
//  ffplayer
//
//  Created by rei6 on 2019/03/21.
//  Copyright © 2019 lithium03. All rights reserved.
//

#ifndef player_base_hpp
#define player_base_hpp

extern "C" {
#include <SDL.h>
#include <SDL_thread.h>
    
#include <SDL_ttf.h>

#include <SDL_image.h>

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libavutil/avstring.h>
#include <libavutil/time.h>
#include <libswresample/swresample.h>
#include <libavfilter/avfilter.h>
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
}

#include <stdio.h>
#include <memory>
#include <queue>
#include <deque>
#include <string>
#include <atomic>
#include <list>

#include "player_param.h"

extern Uint32 messageBase;

class Player;

class PacketQueue
{
private:
    Player *parent = NULL;
    const std::shared_ptr<SDL_mutex> mutex;
    const std::shared_ptr<SDL_cond> cond;
public:
    AVPacketList *first_pkt = NULL, *last_pkt = NULL;
    int nb_packets = 0;
    int size = 0;
    
    PacketQueue(Player *parent);
    ~PacketQueue();
    void AbortQueue();
    int putEOF();
    int put(AVPacket *pkt);
    int get(AVPacket *pkt, int block);
    void flush();
    void clear();
};

class VideoPicture
{
public:
    AVFrame bmp;
    int width = -1, height = -1; /* source height & width */
    bool allocated = false;
    double pts = -1;
    int64_t serial = -1;
    
    VideoPicture(): bmp() { }
    ~VideoPicture();
    bool Allocate(int width, int height);
    void Free();
};

class SubtitlePicture
{
public:
    int type = -1;
    std::unique_ptr<std::shared_ptr<AVSubtitleRect>[]> subrects;
    int numrects = 0;
    uint32_t start_display_time = 0;
    uint32_t end_display_time = 0;
    int subw = -1;
    int subh = -1;
    double pts = NAN;
    int64_t serial = -1;
};

class SubtitlePictureQueue
{
private:
    Player *parent = NULL;
    const std::shared_ptr<SDL_mutex> mutex;
    const std::shared_ptr<SDL_cond> cond;
    std::queue<std::shared_ptr<SubtitlePicture>> queue;
public:
    
    SubtitlePictureQueue(Player *parent);
    ~SubtitlePictureQueue();
    void clear();
    void put(std::shared_ptr<SubtitlePicture> Pic);
    int get(double pts, std::shared_ptr<SubtitlePicture> &Pic);
};


class Player {
public:
    bool            rotate_lock = false;
    bool            display_on = false;
    double          audio_sync_delay = 0;
    double          audio_volume = 100; // 100 = MAX
    bool            audio_mute = false;
    double          duration = NAN;
    double          playtime = NAN;
    double          pos_ratio = 0;
    double          start_skip = NAN;
    std::string     name;
    
    bool   quit = false;
    bool   ishidden = false;
    
    AVFormatContext *pFormatCtx = NULL;
    
    int             videoStream = -1, audioStream = -1;
    int             subtitleStream = -1;

    bool            sync_video = false;

    int64_t         overlay_remove_time = -1;
    std::string     overlay_text;

    bool            pause = false;
    
    int64_t         start_time_org = -1;
    bool            seek_req = false;
    int             seek_flags = 0;
    int64_t         seek_pos = -1;
    double          seek_ratio = NAN;
    int64_t         seek_rel = -1;
    double          prev_pos = 0;
    
    bool            seek_req_backorder = false;
    int             seek_flags_backorder = 0;
    double          seek_ratio_backorder = NAN;
    int64_t         seek_pos_backorder = -1;
    int64_t         seek_rel_backorder = -1;

    SDL_AudioDeviceID audio_deviceID = -1;
    AVStream        *audio_st = NULL;
    std::shared_ptr<AVCodecContext> audio_ctx;
    PacketQueue     audioq;
    uint8_t         audio_buf[MAX_AUDIO_FRAME_SIZE * 10] = {};
    unsigned int    audio_buf_size = 0;
    unsigned int    audio_buf_index = 0;
    double          audio_diff_cum = 0; /* used for AV difference average computation */
    double          audio_diff_avg_coef = 0;
    double          audio_diff_threshold = 0;
    int             audio_diff_avg_count = 0;
    std::shared_ptr<SwrContext>     swr_ctx;
    int             audio_out_sample_rate = 0;
    int             audio_out_channels = 0;
    double          audio_clock = NAN;
    double          audio_clock_start = NAN;
    enum audio_eof_enum {
        playing,
        input_eof,
        output_eof,
        eof,
    }                audio_eof = playing;
    typedef struct AudioParams {
        int freq;
        int channels;
        int64_t channel_layout;
        enum AVSampleFormat fmt;
        int frame_size;
        int bytes_per_sec;
        int audio_volume_dB;
        bool audio_volume_auto;
        int64_t serial;
    } AudioParams;
    AudioParams audio_filter_src = {};
    bool            audio_only = false;
    std::shared_ptr<AVFilterGraph> agraph;
    AVFilterContext *afilt_out = NULL, *afilt_in = NULL;
    int             audio_volume_dB = 0;
    bool            audio_volume_auto = false;
    int64_t         audio_serial = -1;

    bool            audio_pause = false;
    double          audio_callback_time = NAN;
    int             audio_callback_count = 0;

    AVStream        *subtitle_st = NULL;
    std::shared_ptr<AVCodecContext> subtitle_ctx;
    PacketQueue     subtitleq;
    SubtitlePictureQueue subpictq;
    int64_t         subpictq_active_serial = -1;
    double          frame_timer = NAN;
    double          frame_last_pts = NAN;
    double          frame_last_delay = 10e-3;
    bool            force_draw = false;
    std::atomic<long> remove_refresh;
    double          video_delay_to_audio = NAN;

    AVStream        *video_st = NULL;
    std::shared_ptr<AVCodecContext> video_ctx;
    PacketQueue     videoq;
    std::shared_ptr<SwsContext>     sws_ctx;
    double          video_clock = NAN; // pts of last decoded frame / predicted pts of next decoded frame
    double          video_current_pts = NAN; ///<current displayed pts (different from video_clock if frame fifos are used)
    int64_t         video_current_pts_time = -1;  ///<time (av_gettime) at which we updated video_current_pts - used to have running video pts
    double          video_clock_start = NAN;
    bool            video_eof = false;
    bool            video_only = false;
    int             video_width = -1;
    int             video_height = -1;
    int             video_srcwidth = -1;
    int             video_srcheight = -1;
    AVRational      video_SAR = {};
    bool            deinterlace = false;
    
    VideoPicture    pictq[VIDEO_PICTURE_QUEUE_SIZE];
    int             pictq_size = 0, pictq_rindex = 0, pictq_windex = 0;
    VideoPicture*   pictq_prev = NULL;
    int64_t         pictq_active_serial = -1;
    bool            pict_seek_after = true;
    const std::shared_ptr<SDL_mutex> pictq_mutex;
    const std::shared_ptr<SDL_cond>  pictq_cond;

    const std::shared_ptr<SDL_mutex> screen_mutex;

    SDL_Thread      *parse_tid = NULL;
    SDL_Thread      *video_tid = NULL;
    SDL_Thread      *subtitle_tid = NULL;

    TTF_Font *font = NULL;
    SDL_Window *window = NULL;
    SDL_Renderer *renderer = NULL;
    std::shared_ptr<SDL_Texture> texture;
    std::unique_ptr<std::shared_ptr<SDL_Texture>[]> subtitle;
    std::shared_ptr<SDL_Texture> statictexture;
    int subtitlelen = 0;
    uint64_t subserial = -1;
    int subwidth = -1;

    void *param = NULL;
    bool turn = false;
    bool pts_rollover = false;
    bool change_pause = false;
    
    std::shared_ptr<SDL_Texture> image1;
    std::shared_ptr<SDL_Texture> image2;
    std::shared_ptr<SDL_Texture> image3;
    std::shared_ptr<SDL_Texture> image4;
    void(*setwindow)(int32_t) = NULL;
    
    void(*update_info)(void *opaque, int play, double pos, double len);
    
    Player();
    
    int stream_component_open(int stream_index);
    void stream_component_close(int stream_index);
    void stream_cycle_channel(int codec_type);
    void stream_seek(int64_t pos, int rel);
    void stream_seek(double ratio);
    void EventOnSeek(double value, bool frac, bool pre);
    void TogglePause();

    void video_refresh_timer();
    void loading_display();
    void video_display(VideoPicture *vp);
    void audioonly_video_display();
    void subtitle_display(double pts);
    std::shared_ptr<SDL_Surface> subtitle_ass(const char *text);
    void overlay_txt(VideoPicture *vp);
    void overlay_txt(double pts);
    void overlay_info();
    
    int queue_picture(AVFrame *pFrame, double pts);
    VideoPicture *next_picture_queue();

    int audio_decode_frame(uint8_t *audio_buf, int buf_size, double *pts_ptr);
    int synchronize_audio(short *samples, int samples_size, double pts);
    double synchronize_video(AVFrame *src_frame, double pts, double framerate);
    bool configure_audio_filters();
    bool Configure_VideoFilter(AVFilterContext **filt_in, AVFilterContext **filt_out, AVFrame *frame, AVFilterGraph *graph);

    double get_audio_clock();
    double get_video_clock();
    double get_master_clock();

    double get_duration();
    void set_clockduration(double pts);

    void destory_pictures();
    void destory_all_pictures();
    void schedule_refresh(int delay);
    void Redraw();
    void Quit();
    bool IsQuit();
    void Finalize();
};

uint32_t sdl_refresh_timer_cb(uint32_t interval, void *opaque);
uint32_t sdl_internal_refresh_timer_cb(uint32_t interval, void *opaque);
uint32_t timerdisplay_cb(uint32_t interval, void *param);

#endif /* player_base_hpp */
