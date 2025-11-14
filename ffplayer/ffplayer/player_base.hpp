//
//  player_base.hpp
//  fftest
//
//  Created by rei8 on 2019/10/18.
//  Copyright © 2019 lithium03. All rights reserved.
//

#ifndef player_base_hpp
#define player_base_hpp

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libavutil/avutil.h>
#include <libavutil/time.h>
#include <libavutil/avstring.h>
#include <libavutil/opt.h>
#include <libavutil/bprint.h>
#include <libavutil/avutil.h>
#include <libswresample/swresample.h>
#include <libavfilter/avfilter.h>
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
}

#include <string>
#include <thread>
#include <memory>
#include <deque>
#include <queue>
#include <utility>
#include <chrono>
#include <atomic>
#include <list>
#include <sstream>

#include "packetQueue.hpp"
#include "player_param.h"

class Player {
public:
    std::string     name;
    bool            quit = false;
    int             ret = -1;
    
    bool            arib_to_text = false;
    
    AVFormatContext *pFormatCtx = NULL;
    
    enum sync_source {
        sync_audio,
        sync_timer,
    };
    sync_source     sync_type = sync_audio;
    int64_t         master_clock_start = AV_NOPTS_VALUE;
    double          master_clock_offset = std::nan("");
    
    int64_t         audio_last_call = AV_NOPTS_VALUE;
    double          audio_clock_base = std::nan("");
    
    bool            pause = false;
    void setPause(bool value);
    
    typedef class AudioInfo {
    public:
        enum audio_eof_enum {
            playing,
            input_eof,
            output_eof,
            eof,
        };
        typedef struct AudioParams {
            int freq;
            int channels;
            AVChannelLayout ch_layout;
            enum AVSampleFormat fmt;
            int frame_size;
            int bytes_per_sec;
            int audio_volume_dB;
            bool audio_volume_auto;
            int64_t serial;
        } AudioParams;

        int             audioStream = -1;
        std::string     language;
        AVStream        *audio_st = NULL;
        PacketQueue     audioq;
        audio_eof_enum  audio_eof = playing;
        std::shared_ptr<AVCodecContext> audio_ctx;
        AudioParams audio_filter_src = {};

        float           *audio_wav;
        double          pts_base = std::nan("");
        std::mutex      audio_mutex;
        std::condition_variable cond_full;
        std::atomic_ullong read_idx;
        std::atomic_ullong write_idx;
        
        AVChannelLayout ch_layout;
        int             sample_rate = 48000;
        int             buf_length = sample_rate * 1;

        AudioInfo(Player *parent) : audioq(parent), read_idx(0), write_idx(0) {
            av_channel_layout_default(&ch_layout, 2);
            audio_wav = new float[buf_length*ch_layout.nb_channels];
        }
        ~AudioInfo() {
            delete [] audio_wav;
        }
    } AudioInfo;
    AudioInfo audio;

    typedef class SubtitleInfo {
    public:
        int             subtitleStream = -1;
        std::string     language;
        AVStream        *subtitle_st = NULL;
        std::shared_ptr<AVCodecContext> subtitle_ctx;
        PacketQueue     subtitleq;
        SubtitlePictureQueue subpictq;
        int64_t         subpictq_active_serial = -1;
        
        SubtitleInfo(Player *parent) : subtitleq(parent), subpictq(parent) {}
    } SubtitleInfo;
    SubtitleInfo subtitle;
    
    typedef class VideoInfo {
    public:
        int             videoStream = -1;
        std::string     language;
        AVStream        *video_st = NULL;
        std::shared_ptr<AVCodecContext> video_ctx;
        PacketQueue     videoq;
//        std::shared_ptr<SwsContext>     sws_ctx;
        int64_t         video_current_pts_time = -1;

        bool            video_eof = false;
        bool            video_only = false;
        int             video_width = -1;
        int             video_height = -1;
        int             video_srcwidth = -1;
        int             video_srcheight = -1;
        AVRational      video_SAR = {};
        double          video_aspect = 1.0;
        bool            deinterlace = false;

        double          video_clock_start = std::nan("");
        double          video_clock = std::nan("");
        
        VideoPicture    pictq[VIDEO_PICTURE_QUEUE_SIZE];
        int             pictq_size = 0, pictq_rindex = 0, pictq_windex = 0;
        VideoPicture*   pictq_prev = NULL;
        int64_t         pictq_active_serial = -1;
        bool            pict_seek_after = true;
        std::mutex      pictq_mutex;
        std::condition_variable pictq_cond;

        double          frame_timer = std::nan("");
        double          frame_last_pts = std::nan("");
        double          frame_last_delay = 10e-3;

        VideoInfo(Player *parent) : videoq(parent) {}
    } VideoInfo;
    VideoInfo video;

    enum seek_type {
        seek_type_none,
        seek_type_pos,
        seek_type_next,
        seek_type_prev,
    };
    seek_type       seek_req_type = seek_type_none;
    int64_t         seek_pos = AV_NOPTS_VALUE;

    std::thread     parse_thread;
    std::thread     video_thread;
    std::thread     audio_thread;
    std::thread     subtitle_thread;
    std::thread     display_thread;

    void *param = NULL;
    
    Player();

    int stream_component_open(int stream_index);
    void stream_component_close(int stream_index);

    bool Configure_VideoFilter(AVFilterContext **filt_in, AVFilterContext **filt_out, AVFrame *frame, AVFilterGraph *graph);

    int queue_picture(AVFrame *pFrame, double pts);
    double synchronize_video(AVFrame *src_frame, double pts, double framerate);
    VideoPicture *next_picture_queue();
    void video_display(VideoPicture *vp);
    void destory_pictures();
    void destory_all_pictures();

    double get_master_clock();
    double get_duration();

    double load_sound(float *buffer, int num_packet);
    bool configure_audio_filters(AVFilterContext **filt_in, AVFilterContext **filt_out, AVFilterGraph *graph, const AudioInfo::AudioParams &audio_filter_src);
    void clear_soundbufer();
    
    void seek(int64_t pos);
    void seek_chapter(int inc);
    void set_pause(bool pause_state);
    void stream_cycle_channel(int codec_type);
    
    void subtitle_display(VideoPicture *vp);
    
    void Quit();
    bool IsQuit(bool pure = false);
    void Finalize();
};

#endif /* player_base_hpp */
