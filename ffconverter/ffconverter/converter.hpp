//
//  converter.hpp
//  ffconverter
//
//  Created by rei8 on 2019/09/06.
//  Copyright © 2019 lithium03. All rights reserved.
//

#ifndef converter_hpp
#define converter_hpp

#include <stdio.h>

#include <memory>
#include <queue>
#include <deque>
#include <string>
#include <atomic>
#include <list>
#include <thread>
#include <condition_variable>
#include <mutex>
#include <sstream>

#include "converter_param.h"

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <libavfilter/avfilter.h>
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
#include <libavutil/bprint.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libavutil/avstring.h>
#include <libavutil/time.h>
}

#include "packetQueue.hpp"

class Converter {
public:
    bool   quit = false;
    bool   ishidden = false;
    
    AVFormatContext *pFormatCtx = NULL;
    
    std::vector<int> videoStream;
    std::vector<int> audioStream;
    std::vector<int> subtitleStream;
    int             bestVideoStream = -1;
    int             bestAudioStream = -1;
    int             bestSubtileStream = -1;
    int             main_video = -1;
    int             main_subtitle = -1;

    bool            arib_to_text = true;
    
    bool            sync_video = false;
    bool            pause = false;
    
    enum audio_eof_enum {
        playing,
        input_eof,
        output_eof,
        eof,
    };
    typedef struct AudioParams {
        int freq;
        int channels;
        AVChannelLayout channel_layout;
        enum AVSampleFormat fmt;
        int frame_size;
        int bytes_per_sec;
        int audio_volume_dB;
        bool audio_volume_auto;
        int64_t serial;
    } AudioParams;
    class AudioStreamInfo {
    public:
        AVStream        *audio_st = NULL;
        std::string     language;
        PacketQueue     audioq;
        audio_eof_enum  audio_eof = playing;
        AudioParams audio_filter_src = {};
        std::shared_ptr<AVCodecContext> audio_ctx;
        int64_t         audio_last_pts_t = AV_NOPTS_VALUE;
        double          audio_last_pts = NAN;
        double          audio_clock_start = NAN;
        int64_t         audio_start_pts = AV_NOPTS_VALUE;
        uint64_t        frame_count = 0;
        bool            absent = false;
        bool            main_audio = false;
        bool            present = false;
        bool            invalid_pts = false;
        bool            audio_fin = false;

        AudioStreamInfo(Converter *parent): audioq(parent) {
        }
    };
    std::vector<std::shared_ptr<AudioStreamInfo> >  audio_info;

    class SubtitleStreamInfo {
    public:
        AVStream        *subtitle_st = NULL;
        std::string     language;
        bool            isText;
        int             textIndex;
        std::shared_ptr<AVCodecContext> subtitle_ctx;
        PacketQueue     subtitleq;
        SubtitlePictureQueue subpictq;
        int64_t         subpictq_active_serial = -1;

        SubtitleStreamInfo(Converter *parent): subtitleq(parent), subpictq(parent){
        }
    };
    std::vector<std::shared_ptr<SubtitleStreamInfo> >  subtitle_info;
    AVRational subtitle_timebase = AV_TIME_BASE_Q;

    class VideoStreamInfo {
    public:
        AVStream        *video_st = NULL;
        std::string     language;
        std::shared_ptr<AVCodecContext> video_ctx;
        PacketQueue     videoq;
        std::shared_ptr<SwsContext>     sws_ctx;
        int64_t         video_current_pts_time = -1;  ///<time (av_gettime) at which we updated video_current_pts - used to have running video pts
        bool            video_eof = false;
        bool            video_fin = false;
        bool            video_only = false;
        int             video_width = -1;
        int             video_height = -1;
        int             video_srcwidth = -1;
        int             video_srcheight = -1;
        AVRational      video_SAR = {};
        double          video_aspect = 1.0;
        bool            deinterlace = false;

        double          video_clock_start = NAN;
        int64_t         video_start_pts = AV_NOPTS_VALUE;
        int64_t         video_prev_pts = AV_NOPTS_VALUE;

        VideoStreamInfo(Converter *parent): videoq(parent) {
        }
    };
    std::vector<std::shared_ptr<VideoStreamInfo> >  video_info;

    double          audio_pts_delta = NAN;
    int             main_audio = -1;

    double          media_duration = 0;
    
    std::thread     parse_thread;
    std::vector<std::thread>    video_thread;
    std::vector<std::thread>    audio_thread;
    std::vector<std::thread>    subtitle_thread;
    
    void *param = NULL;
    
    int stream_component_open(int stream_index);
    void stream_component_close(int stream_index);
    
    bool Configure_VideoFilter(AVFilterContext **filt_in, AVFilterContext **filt_out, AVFrame *frame, AVFilterGraph *graph, const VideoStreamInfo *video);
    bool configure_audio_filters(AVFilterContext **filt_in, AVFilterContext **filt_out, AVFilterGraph *graph, const AudioParams &audio_filter_src, int audio_out_sample_rate, const AVChannelLayout &audio_out_channel_layout);

    void subtitle_overlay(AVFrame &output, double pts);
    
    void Quit();
    bool IsQuit(bool pure = false);
    void Finalize();
};

#endif /* converter_hpp */
