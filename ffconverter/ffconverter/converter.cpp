//
//  converter.cpp
//  ffconverter
//
//  Created by rei8 on 2019/09/06.
//  Copyright © 2019 lithium03. All rights reserved.
//

#include "converter.hpp"

AVPacket flush_pkt;
AVPacket eof_pkt;
AVPacket abort_pkt;

extern char *FLUSH_STR;
extern char *EOF_STR;
extern char *ABORT_STR;

#ifdef __cplusplus
extern "C" {
#endif /* __cplusplus */
    
    void decode_thread(struct convert_param *stream);
    void audio_dummy_thread(Converter *is);
    void video_dummy_thread(Converter *is);

    void setParam(struct convert_param * param)
    {
        Converter *convert = new Converter();
        param->converter = convert;
        convert->param = param;

        convert->arib_to_text = param->arib_convert_text != 0;
    }
    
    void freeParam(struct convert_param * param)
    {
        printf("freeParam\n");
        if(!param) return;
        delete (Converter *)param->converter;
        param->converter = nullptr;
    }
    
    int createParseThread(struct convert_param * param) {
        if(!param) return -1;
        if(!(Converter *)param->converter) return -1;
        ((Converter *)param->converter)->parse_thread = std::thread(decode_thread, param);
        return 0;
    }
    
    int waitParseThread(struct convert_param * param) {
        if(!param) return -1;
        if(!(Converter *)param->converter) return -1;
        ((Converter *)param->converter)->parse_thread.join();
        ((Converter *)param->converter)->Finalize();
        return 0;
    }
    
    int cancelConvert(struct convert_param * param) {
        ((Converter *)param->converter)->Quit();
        return 0;
    }
    
#ifdef __cplusplus
}
#endif /* __cplusplus */

//***********************************************************************

void decode_thread(struct convert_param *stream)
{
    av_log(NULL, AV_LOG_INFO, "decode_thread start\n");

    int64_t video_last = AV_NOPTS_VALUE;
    std::vector<int64_t> audio_last;
    int64_t packet_count = -1;

    Converter *converter = (Converter *)stream->converter;
    
    converter->videoStream.clear();
    converter->audioStream.clear();
    converter->subtitleStream.clear();

    converter->pFormatCtx = avformat_alloc_context();
    unsigned char *buffer = (unsigned char *)av_malloc(1024*1024);
    AVIOContext *pIoCtx = avio_alloc_context(
                                             buffer,
                                             1024*1024,
                                             0,
                                             stream->stream,
                                             stream->read_packet,
                                             NULL,
                                             stream->seek
                                             );
    AVPacket packet = { 0 };
    bool error = false;
    converter->pFormatCtx->pb = pIoCtx;
    char *filename = stream->name;
    double start_skip = stream->start;

    std::vector<char> s_langs;
    std::vector<char *> s_langp;
    std::vector<char> v_langs;
    std::vector<char *> v_langp;
    std::vector<char *> sub_langp;
    int select_idx[2] = {-1, -1};
    char *cp;
    int main_audio = -1;
    int main_subtitle = -1;
    int search_count = 10000;
    
    std::vector<int> audioStream;
    std::vector<int> videoStream;
    std::vector<int> subtitleStream;
    std::vector<int> txt_subtitleStream;
    std::vector<int> img_subtitleStream;

    av_log(NULL, AV_LOG_VERBOSE, "avformat_open_input()\n");
    // Open video file
    if (avformat_open_input(&converter->pFormatCtx, filename, NULL, NULL) != 0) {
        printf("avformat_open_input() failed %s\n", filename);
        goto failed_open;
    }
    
    while(search_count > 0 && !converter->quit) {
        if(av_read_frame(converter->pFormatCtx, &packet) < 0)
            break;
        av_packet_unref(&packet);
        search_count--;
    }
    av_seek_frame(converter->pFormatCtx, -1, 0, 0);
    
    if(converter->quit) {
        goto failed_run;
    }
    
    av_log(NULL, AV_LOG_VERBOSE, "avformat_find_stream_info()\n");
    // Retrieve stream information
    if (avformat_find_stream_info(converter->pFormatCtx, NULL) < 0) {
        printf("avformat_find_stream_info() failed %s\n", filename);
        goto failed_run;
    }
    
    av_log(NULL, AV_LOG_VERBOSE, "av_dump_format()\n");
    // Dump information about file onto standard error
    av_dump_format(converter->pFormatCtx, 0, filename, 0);
    
    for(unsigned int stream_index = 0; stream_index<converter->pFormatCtx->nb_streams; stream_index++)
        converter->pFormatCtx->streams[stream_index]->discard = AVDISCARD_ALL;
    
    av_log(NULL, AV_LOG_VERBOSE, "av_find_best_stream()\n");
    for(unsigned int stream_index = 0; stream_index<converter->pFormatCtx->nb_streams; stream_index++) {
        if(converter->pFormatCtx->streams[stream_index]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            av_log(NULL, AV_LOG_INFO, "audio stream %d\n", stream_index);
            audioStream.push_back(stream_index);
            audio_last.push_back(AV_NOPTS_VALUE);
        }
        else if(converter->pFormatCtx->streams[stream_index]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            av_log(NULL, AV_LOG_INFO, "video stream %d\n", stream_index);
            videoStream.push_back(stream_index);
        }
        else if(converter->pFormatCtx->streams[stream_index]->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
            av_log(NULL, AV_LOG_INFO, "subtile stream %d\n", stream_index);
            subtitleStream.push_back(stream_index);
        }
    }

    converter->bestVideoStream = av_find_best_stream(converter->pFormatCtx, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    converter->bestAudioStream = av_find_best_stream(converter->pFormatCtx, AVMEDIA_TYPE_AUDIO, -1, converter->bestVideoStream, NULL, 0);
    converter->bestSubtileStream = av_find_best_stream(converter->pFormatCtx, AVMEDIA_TYPE_SUBTITLE, -1, converter->bestVideoStream, NULL, 0);

    for(auto audio_index: audioStream) {
        av_log(NULL, AV_LOG_VERBOSE, "audio stream open()\n");
        if(converter->stream_component_open(audio_index) == 0)
            converter->audioStream.push_back(audio_index);
    }

    for(int i = 0; i < converter->audioStream.size(); i++) {
        if(converter->audioStream[i] == converter->bestAudioStream) {
            main_audio = i;
            break;
        }
    }

    for(const auto &audio: converter->audio_info) {
        s_langs.resize(s_langs.size() + audio->language.size() + 1);
    }
    s_langs.push_back(0);
    cp = &s_langs[0];
    for(const auto &audio: converter->audio_info) {
        s_langp.push_back(cp);
        strcpy(cp, audio->language.c_str());
        cp += audio->language.size() + 1;
    }

    for(auto video_index: videoStream) {
        av_log(NULL, AV_LOG_VERBOSE, "video stream open()\n");
        if (converter->stream_component_open(video_index) == 0){
            converter->videoStream.push_back(video_index);
        }
    }
    for(auto subtitle_index: subtitleStream) {
        av_log(NULL, AV_LOG_VERBOSE, "subtitle stream open()\n");
        if (converter->stream_component_open(subtitle_index) == 0){
            converter->subtitleStream.push_back(subtitle_index);
        }
    }

    for(int i = 0; i < converter->subtitleStream.size(); i++) {
        if(converter->subtitleStream[i] == converter->bestSubtileStream) {
            main_subtitle = i;
            break;
        }
    }

    for(int i = 0; i < converter->subtitle_info.size(); i++) {
        auto subtitle = converter->subtitle_info[i];
        auto id = subtitle->subtitle_st->codecpar->codec_id;
        auto desc = avcodec_descriptor_get(id);
        if (id == AV_CODEC_ID_ARIB_CAPTION) {
            if(converter->arib_to_text) {
                txt_subtitleStream.push_back(converter->subtitleStream[i]);
                subtitle->isText = true;
                subtitle->textIndex = (int)txt_subtitleStream.size()-1;
            }
            else {
                img_subtitleStream.push_back(converter->subtitleStream[i]);
                subtitle->isText = false;
            }
        }
        else if (desc != NULL) {
            if(desc->props & AV_CODEC_PROP_BITMAP_SUB){
                img_subtitleStream.push_back(converter->subtitleStream[i]);
                subtitle->isText = false;
            }
            if(desc->props & AV_CODEC_PROP_TEXT_SUB){
                txt_subtitleStream.push_back(converter->subtitleStream[i]);
                subtitle->isText = true;
                subtitle->textIndex = (int)txt_subtitleStream.size()-1;
            }
        }
    }

    v_langs.clear();
    for(int i = 0; i < txt_subtitleStream.size(); i++) {
        for(int j = 0; j < converter->subtitle_info.size(); j++){
            if (txt_subtitleStream[i] == converter->subtitleStream[j]) {
                v_langs.resize(v_langs.size() + converter->subtitle_info[j]->language.size() + 1);
                break;
            }
        }
    }
    v_langs.push_back(0);
    cp = &v_langs[0];
    for(int i = 0; i < txt_subtitleStream.size(); i++) {
        for(int j = 0; j < converter->subtitle_info.size(); j++){
            if (txt_subtitleStream[i] == converter->subtitleStream[j]) {
                sub_langp.push_back(cp);
                strcpy(cp, converter->subtitle_info[j]->language.c_str());
                cp += converter->subtitle_info[j]->language.size() + 1;
                break;
            }
        }
    }

    if (converter->audio_info.size() == 0) {
        char und[] = "und";
        char *buf[] = {und};
        stream->stream_count(stream->stream, 1, 0, buf, (int)txt_subtitleStream.size(), main_subtitle, sub_langp.data());
    }
    else {
        stream->stream_count(stream->stream, (int)converter->audio_info.size(), main_audio, s_langp.data(), (int)txt_subtitleStream.size(), main_subtitle, sub_langp.data());
    }

    if (converter->video_info.size() > 0) {
        v_langs.clear();
        sub_langp.clear();
        for(const auto &video: converter->video_info) {
            v_langs.resize(v_langs.size() + video->language.size() + 1);
        }
        for(int i = 0; i < img_subtitleStream.size(); i++) {
            for(int j = 0; j < converter->subtitle_info.size(); j++){
                if (img_subtitleStream[i] == converter->subtitleStream[j]) {
                    v_langs.resize(v_langs.size() + converter->subtitle_info[j]->language.size() + 1);
                    break;
                }
            }
        }
        cp = &v_langs[0];
        for(const auto &video: converter->video_info) {
            v_langp.push_back(cp);
            strcpy(cp, video->language.c_str());
            cp += video->language.size() + 1;
        }
        for(int i = 0; i < img_subtitleStream.size(); i++) {
            for(int j = 0; j < converter->subtitle_info.size(); j++){
                if (img_subtitleStream[i] == converter->subtitleStream[j]) {
                    sub_langp.push_back(cp);
                    strcpy(cp, converter->subtitle_info[j]->language.c_str());
                    cp += converter->subtitle_info[j]->language.size() + 1;
                    break;
                }
            }
        }
        select_idx[0] = converter->bestVideoStream;
        select_idx[1] = converter->bestSubtileStream;
        
        if(converter->video_info.size() > 1 || img_subtitleStream.size() > 0) {
            stream->stream_select(stream->stream, select_idx, (int)converter->video_info.size(), converter->videoStream.data(), v_langp.data(), (int)img_subtitleStream.size(), img_subtitleStream.data(), sub_langp.data());
        }
        
        if(select_idx[0] < 0) {
            goto failed_run;
        }

        for(int i = 0; i < converter->subtitleStream.size(); i++) {
            if(converter->subtitleStream[i] == select_idx[1]) {
                converter->main_subtitle = i;
                break;
            }
        }
        for(int i = 0; i < converter->videoStream.size(); i++) {
            if(converter->videoStream[i] == select_idx[0]) {
                converter->main_video = i;
                break;
            }
        }
    }
    else {
        std::shared_ptr<Converter::VideoStreamInfo> info(new Converter::VideoStreamInfo(converter));
        info->video_clock_start = 0;
        info->video_start_pts = 0;
        info->video_eof = true;
        converter->video_info.push_back(info);
        converter->main_video = 0;
    }

    if (converter->videoStream.size() == 0 || converter->audioStream.size() == 0) {
        if (converter->videoStream.size() == 0) {
            av_log(NULL, AV_LOG_VERBOSE, "video missing\n");
            converter->video_thread.push_back(std::thread(video_dummy_thread, converter));
        }
        else {
            av_log(NULL, AV_LOG_VERBOSE, "audio missing\n");
            converter->audio_thread.push_back(std::thread(audio_dummy_thread, converter));
        }
    }
    else {
        if(converter->main_video < 0) {
            goto failed_run;
        }
    }

    if(converter->IsQuit()) {
        goto failed_run;
    }
    
    if (converter->pFormatCtx->duration) {
        converter->media_duration = converter->pFormatCtx->duration / 1000000.0;
    }
    else if (converter->videoStream.size() > 0 && converter->pFormatCtx->streams[converter->main_video]->duration) {
        converter->media_duration = converter->pFormatCtx->streams[converter->main_video]->duration / 1000000.0;
    }
    else if (converter->audioStream.size() > 0 && converter->pFormatCtx->streams[main_audio]->duration) {
        converter->media_duration = converter->pFormatCtx->streams[main_audio]->duration / 1000000.0;
    }
    stream->set_duration(stream->stream, converter->media_duration);

    stream->wait_to_start(stream->stream);
    if (converter->IsQuit()) {
        goto finish;
    }

    // main decode loop
    av_log(NULL, AV_LOG_INFO, "decode_thread read loop\n");
    for (;;) {
        if (converter->IsQuit()) {
            goto finish;
        }
  
        if (converter->videoStream.size() > 0) {
            bool isFull = false;
            for(auto video: converter->video_info){
                if(video->videoq.size() > MAX_VIDEOQ_SIZE) {
                    isFull = true;
                    break;
                }
            }
            if(isFull) {
                av_usleep(10*1000);
                continue;
            }
        }
        else if (converter->audioStream.size() > 0) {
            bool isFull = false;
            for(auto audio: converter->audio_info){
                if(audio->audioq.size() > MAX_AUDIOQ_SIZE) {
                    isFull = true;
                    break;
                }
            }
            if(isFull) {
                av_usleep(10*1000);
                continue;
            }
        }
        packet_count++;
        int ret1 = av_read_frame(converter->pFormatCtx, &packet);
        if (ret1 < 0) {
            av_packet_unref(&packet);
            if (ret1 == AVERROR(EAGAIN))
                continue;
            if ((ret1 == AVERROR_EOF) || (ret1 = AVERROR(EIO))) {
                if (error || converter->pFormatCtx->pb->eof_reached) {
                    if (ret1 == AVERROR_EOF) {
                        av_log(NULL, AV_LOG_INFO, "decoder EOF\n");
                    }
                    else {
                        av_log(NULL, AV_LOG_INFO, "decoder I/O Error\n");
                    }
                    if (converter->videoStream.size() > 0) {
                        av_log(NULL, AV_LOG_INFO, "video EOF request\n");
                        for(auto video: converter->video_info) {
                            video->videoq.putEOF();
                        }
                    }
                    if (converter->audioStream.size() > 0) {
                        av_log(NULL, AV_LOG_INFO, "audio EOF request\n");
                        for(auto audio: converter->audio_info) {
                            audio->audioq.putEOF();
                        }
                    }
                    if (converter->subtitleStream.size() > 0) {
                        av_log(NULL, AV_LOG_INFO, "subtitle EOF request\n");
                        for(auto subtitle: converter->subtitle_info) {
                            subtitle->subtitleq.putEOF();
                        }
                    }
                    
                    break;
                }
                error = true;
            }
            char buf[AV_ERROR_MAX_STRING_SIZE];
            char *errstr = av_make_error_string(buf, AV_ERROR_MAX_STRING_SIZE, ret1);
            av_log(NULL, AV_LOG_ERROR, "error av_read_frame() %d %s\n", ret1, errstr);
            continue;
        }
        
        if (!isnan(start_skip)) {
            av_packet_unref(&packet);
            int64_t start_time_org = 0;
            if(converter->pFormatCtx->start_time != AV_NOPTS_VALUE)
                start_time_org = converter->pFormatCtx->start_time;
            start_skip -= 1;
            if(start_skip > 0) {
                printf("start skip %f sec\n", start_skip);
                int64_t seek_pos = start_skip * AV_TIME_BASE + start_time_org;
                int stream_index = -1;
                int ret1 = av_seek_frame(converter->pFormatCtx, stream_index, seek_pos, 0);
                if (ret1 < 0) {
                    char buf[AV_ERROR_MAX_STRING_SIZE];
                    char *errstr = av_make_error_string(buf, AV_ERROR_MAX_STRING_SIZE, ret1);
                    av_log(NULL, AV_LOG_ERROR, "error avformat_seek_file() %d %s\n", ret1, errstr);
                    error = true;
                }
            }
            start_skip = NAN;
            continue;
        }
        
        if((packet.flags & (AV_PKT_FLAG_CORRUPT | AV_PKT_FLAG_DISCARD)) > 0) {
            av_packet_unref(&packet);
            av_log(NULL, AV_LOG_INFO, "flag %d %lld\n", packet.flags, packet.pts);
            continue;
        }

        error = false;
        bool found = false;
        // Is this a packet from the video stream?
        for(int i = 0; i < converter->videoStream.size(); i++) {
            if (packet.stream_index == converter->videoStream[i]) {
                av_log(NULL, AV_LOG_INFO, "video %d packet %lld\n", packet.stream_index, packet_count);
                if(converter->video_info[i]->videoq.put(&packet) == 0) {
                    converter->video_info[i]->video_eof = false;
                }
                video_last = packet_count;
                found = true;
                break;
            }
        }
        if (!found) {
            for(int i = 0; i < converter->subtitleStream.size(); i++) {
                if (packet.stream_index == converter->subtitleStream[i]) {
                    av_log(NULL, AV_LOG_INFO, "subtile %d packet %lld\n", packet.stream_index, packet_count);
                    if(av_q2d(converter->pFormatCtx->streams[packet.stream_index]->time_base) > 0) {
                        printf("subtitle timebase %f\n", av_q2d(converter->pFormatCtx->streams[packet.stream_index]->time_base));
                        converter->subtitle_timebase = converter->pFormatCtx->streams[packet.stream_index]->time_base;
                    }
                    converter->subtitle_info[i]->subtitleq.put(&packet);
                    found = true;
                    break;
                }
            }
        }
        if (!found) {
            // sound stream id check
            bool main_packet = false;
            for(int i = 0; i < converter->audioStream.size(); i++) {
                if (packet.stream_index == converter->audioStream[i]) {
                    av_log(NULL, AV_LOG_INFO, "audio %d packet %lld\n", packet.stream_index, packet_count);
                    converter->audio_info[i]->absent = false;
                    if(converter->audio_info[i]->audioq.put(&packet) == 0) {
                        converter->audio_info[i]->audio_eof = Converter::audio_eof_enum::playing;
                    }
                    audio_last[i] = packet_count;
                    if(converter->audio_info[i]->present) {
                        if(converter->main_audio < 0 || (video_last != AV_NOPTS_VALUE && video_last - audio_last[converter->main_audio] > 1000)) {
                            av_log(NULL, AV_LOG_INFO, "main audio %d set packet %lld\n", i, packet_count);
                            converter->main_audio = i;
                            for(int j = 0; j < converter->audioStream.size(); j++) {
                                if (i != j) converter->audio_info[j]->main_audio = false;
                            }
                            converter->audio_info[i]->main_audio = true;
                        }
                    }
                    if(converter->main_audio == i) {
                        main_packet = true;
                    }
                    found = true;
                    break;
                }
            }
            
            // if stream is inactive, put a main sound packet
            if (main_packet) {
                // after 1000 packets but not start yet
                if(video_last != AV_NOPTS_VALUE && video_last > 1000) {
                    for(int i = 0; i < converter->audioStream.size(); i++) {
                        if (i == converter->main_audio) continue;
                        // not start yet
                        if(audio_last[i] == AV_NOPTS_VALUE) {
                            converter->audio_info[i]->absent = true;
                        }
                    }
                }
                
                // packet not provided after last 1000 packet
                for(int i = 0; i < converter->audioStream.size(); i++) {
                    if (i == converter->main_audio) continue;
                    // not start yet
                    if(audio_last[i] == AV_NOPTS_VALUE) continue;
                    // long absent packet
                    if(video_last - audio_last[i] > 1000) {
                        converter->audio_info[i]->absent = true;
                    }
                }
            }
        }
        av_packet_unref(&packet);
    }
    /* all done - wait for it */
    while (!converter->IsQuit(true)) {
        av_usleep(100*1000);
    }
    
finish:
    ;
failed_run:
    converter->Quit();
    while (!converter->IsQuit(true)) {
        av_usleep(100*1000);
    }
    for(auto video_index: converter->videoStream) {
        av_log(NULL, AV_LOG_VERBOSE, "video stream close()\n");
        converter->stream_component_close(video_index);
    }
    for(auto audio_index: converter->audioStream) {
        av_log(NULL, AV_LOG_VERBOSE, "audio stream close()\n");
        converter->stream_component_close(audio_index);
    }
    for(auto subtitle_index: converter->subtitleStream) {
        av_log(NULL, AV_LOG_VERBOSE, "subtitle stream close()\n");
        converter->stream_component_close(subtitle_index);
    }
    avformat_close_input(&converter->pFormatCtx);
failed_open:
    av_freep(&pIoCtx);
    av_log(NULL, AV_LOG_INFO, "decode_thread end\n");
}

void video_dummy_thread(Converter *is)
{
    int index = 0;
    av_log(NULL, AV_LOG_INFO, "video_thread %d start\n", index);
    auto encode = ((struct convert_param *)is->param)->encode;
    auto finish = ((struct convert_param *)is->param)->finish;
    auto stream = ((struct convert_param *)is->param)->stream;
    int out_width = 1920;
    int out_height = 1080;
    AVFrame outputFrame = { 0 };
    outputFrame.format = AVPixelFormat::AV_PIX_FMT_YUV420P;
    outputFrame.width = out_width;
    outputFrame.height = out_height;
    av_frame_get_buffer(&outputFrame, 32);
    memset(outputFrame.data[0], 0, out_height * outputFrame.linesize[0]);
    memset(outputFrame.data[1], 127, out_height / 2 * outputFrame.linesize[1]);
    memset(outputFrame.data[2], 127, out_height / 2 * outputFrame.linesize[2]);
    double pts = 0;
    int64_t count = 0;

    av_log(NULL, AV_LOG_INFO, "video_thread %d read loop\n", index);
    while (true) {
        if (is->IsQuit()) break;

        int key = 1;
        if (pts > is->media_duration) {
            break;
        }
        pts = (double)(count++) * 1001 / 30000;
        encode(stream, pts, key, outputFrame.data, outputFrame.linesize, outputFrame.height);
    }
loopend:
    av_log(NULL, AV_LOG_INFO, "video_thread loop end %d\n", index);
    is->video_info[index]->videoq.clear();
    finish(stream);
finish:
    av_frame_unref(&outputFrame);
    is->video_info[index]->video_eof = true;
    av_log(NULL, AV_LOG_INFO, "video_thread end %d\n", index);
    is->video_info[index]->video_fin = true;
    return;
}


void video_thread(Converter *is, int index)
{
    av_log(NULL, AV_LOG_INFO, "video_thread %d start\n", index);
    auto encode = ((struct convert_param *)is->param)->encode;
    auto finish = ((struct convert_param *)is->param)->finish;
    auto stream = ((struct convert_param *)is->param)->stream;
    auto duration = ((struct convert_param *)is->param)->duration;
    AVPacket packet = { 0 }, *inpkt = &packet;
    AVCodecContext *video_ctx = is->video_info[index]->video_ctx.get();
    AVFrame frame1 = { 0 };
    AVFrame *inframe = &frame1;
    AVFrame frame2 = { 0 };
    std::shared_ptr<AVFilterGraph> graph(avfilter_graph_alloc(), [](AVFilterGraph *ptr) { avfilter_graph_free(&ptr); });
    AVFilterContext *filt_out = NULL, *filt_in = NULL;
    int last_w = 0;
    int last_h = 0;
    AVPixelFormat last_format = (AVPixelFormat)-2;
    int64_t last_serial = 0, serial = 0;
    SwsContext *sws_context = NULL;
    int out_width = 1920;
    int out_height = 1080;
    //int out_width = 1280;
    //int out_height = 720;
    AVFrame outputFrame = { 0 };
    outputFrame.format = AVPixelFormat::AV_PIX_FMT_YUV420P;
    outputFrame.width = out_width;
    outputFrame.height = out_height;
    av_frame_get_buffer(&outputFrame, 32);
    double pts = 0;

    switch (is->video_info[index]->video_ctx->codec_id)
    {
        case AV_CODEC_ID_MJPEG:
        case AV_CODEC_ID_MJPEGB:
        case AV_CODEC_ID_LJPEG:
            is->video_info[index]->deinterlace = false;
            break;
        default:
            is->video_info[index]->deinterlace = true;
            break;
    }
    
    while(is->main_video < 0) {
        if(is->IsQuit()) goto finish;
        av_usleep(10*1000);
    }
    
    av_log(NULL, AV_LOG_INFO, "video_thread %d read loop\n", index);
    while (true) {
        if (is->video_info[index]->video_eof) {
            break;
        }
        else if (is->video_info[index]->videoq.get(&packet, 1) < 0) {
            // means we quit getting packets
            av_log(NULL, AV_LOG_INFO, "video Quit %d\n", index);
            is->video_info[index]->video_eof = true;
            packet = { 0 };
            break;
        }
        if (is->IsQuit()) break;
        
        if(packet.data) {
            if (strcmp((char *)packet.data, FLUSH_STR) == 0) {
                av_log(NULL, AV_LOG_INFO, "video buffer flush %d\n", index);
                avcodec_flush_buffers(video_ctx);
                packet = { 0 };
                inpkt = &packet;
                inframe = &frame1;
                is->video_info[index]->video_eof = false;
                continue;
            }
            if (strcmp((char *)packet.data, ABORT_STR) == 0) {
                av_log(NULL, AV_LOG_INFO, "video buffer ABORT %d\n", index);
                is->video_info[index]->video_eof = true;
                packet = { 0 };
                break;
            }
            if (strcmp((char *)packet.data, EOF_STR) == 0) {
                av_log(NULL, AV_LOG_INFO, "video buffer EOF %d\n", index);
                packet = { 0 };
                inpkt = NULL;
            }
        }
        
        if(is->main_video != index) {
            if (inpkt){
                av_packet_unref(inpkt);
                continue;
            }
            else {
                break;
            }
        }

        // send packet to codec context
        if (avcodec_send_packet(video_ctx, inpkt) >= 0) {
            if (inpkt) av_packet_unref(inpkt);

            // Decode video frame
            int ret;
            while ((ret = avcodec_receive_frame(video_ctx, &frame1)) >= 0 || ret == AVERROR_EOF) {
                if (ret == AVERROR_EOF){
                    av_log(NULL, AV_LOG_INFO, "video EOF %d\n", index);
                    inframe = NULL;
                }
                
                int key = 0;
                if (inframe) {
                    if(frame1.decode_error_flags != 0) {
                        av_log(NULL, AV_LOG_INFO, "video decode error %d %d\n", frame1.decode_error_flags, index);
                        //av_frame_unref(inframe);
                        //continue;
                    }
                    
                    if (frame1.width != last_w ||
                        frame1.height != last_h ||
                        frame1.format != last_format ||
                        last_serial != serial) {
                        graph = std::shared_ptr<AVFilterGraph>(avfilter_graph_alloc(), [](AVFilterGraph *ptr) { avfilter_graph_free(&ptr); });
                        if (!is->Configure_VideoFilter(&filt_in, &filt_out, &frame1, graph.get(), is->video_info[index].get())) {
                            is->Quit();
                            return;
                        }
                        last_w = frame1.width;
                        last_h = frame1.height;
                        last_format = (AVPixelFormat)frame1.format;
                        last_serial = serial;
                        is->video_info[index]->video_SAR = frame1.sample_aspect_ratio;
                        is->video_info[index]->video_aspect = av_q2d(frame1.sample_aspect_ratio);
                        is->video_info[index]->video_height = filt_out->inputs[0]->h;
                        is->video_info[index]->video_width = filt_out->inputs[0]->w;
                        is->video_info[index]->video_srcheight = frame1.height;
                        is->video_info[index]->video_srcwidth = frame1.width;
                    }
                    //printf("key %d\n", frame1.key_frame);
                }
                
                
                if (av_buffersrc_write_frame(filt_in, inframe) < 0){
                    av_frame_unref(inframe);
                    goto loopend;
                }
                
                if (inframe) av_frame_unref(inframe);
                if (!filt_out) break;
                while ((ret = av_buffersink_get_frame(filt_out, &frame2)) >= 0) {
                    
                    key = frame2.flags & AV_FRAME_FLAG_KEY;
                    //printf("key2 %d\n", key);
                    sws_context = sws_getCachedContext(sws_context,
                                                       frame2.width, frame2.height,
                                                       (AVPixelFormat)frame2.format,
                                                       frame2.width, frame2.height,
                                                       AVPixelFormat::AV_PIX_FMT_YUV420P,
                                                       SWS_BICUBIC, NULL, NULL, NULL);
                    
                    int64_t pts_t;
                    if ((pts_t = frame2.best_effort_timestamp) != AV_NOPTS_VALUE) {
                        //av_log(NULL, AV_LOG_INFO, "video pts %lld\n", pts_t);
                        if(is->video_info[index]->video_prev_pts != AV_NOPTS_VALUE && is->video_info[index]->video_prev_pts > 0x1FFFFFFFF && pts_t < is->video_info[index]->video_prev_pts) {
                            av_log(NULL, AV_LOG_INFO, "video pts wrap-around %lld->%lld %d\n", is->video_info[index]->video_prev_pts, pts_t, index);

                            pts_t += 0x1FFFFFFFF;
                        }
                        if(is->video_info[index]->video_prev_pts != AV_NOPTS_VALUE && pts_t < is->video_info[index]->video_prev_pts) {
                            av_log(NULL, AV_LOG_INFO, "video pts back ignore %d\n", index);

                            av_frame_unref(&frame2);
                            continue;
                        }
                        else {
                            pts = pts_t * av_q2d(is->video_info[index]->video_st->time_base);
                            //av_log(NULL, AV_LOG_INFO, "video clock %f\n", pts);
                            
                            if (isnan(is->video_info[index]->video_clock_start)) {
                                av_log(NULL, AV_LOG_INFO, "video start pts %f, %lld, %d\n", pts, pts_t, index);
                                is->video_info[index]->video_clock_start = pts;
                                is->video_info[index]->video_start_pts = pts_t;
                            }
                            pts = (pts_t - is->video_info[index]->video_start_pts) * av_q2d(is->video_info[index]->video_st->time_base);
                        }
                    }
                    //av_log(NULL, AV_LOG_INFO, "video pts %f\n", pts);
                    if(!isnan(duration) && pts > duration) {
                        is->Quit();
                    }

                    sws_scale(sws_context, frame2.data,
                              frame2.linesize, 0, frame2.height,
                              outputFrame.data, outputFrame.linesize);
                    av_frame_unref(&frame2);

                    is->subtitle_overlay(outputFrame, pts+is->video_info[index]->video_clock_start);
                    
                    encode(stream, pts, key, outputFrame.data, outputFrame.linesize, outputFrame.height);
                    is->video_info[index]->video_prev_pts = pts_t;
                } //while(av_buffersink_get_frame)
                
                if (!inframe) {
                    break;
                }
            } //while(avcodec_receive_frame)
            
        } //if(avcodec_send_packet)
        else {
            if (inpkt) av_packet_unref(inpkt);
        }
        
        if (!inframe) {
            is->video_info[index]->video_eof = true;
        }
    }//while(true)
loopend:
    av_log(NULL, AV_LOG_INFO, "video_thread loop end %d\n", index);
    is->video_info[index]->videoq.clear();
    sws_freeContext(sws_context);
    finish(stream);
finish:
    av_frame_unref(&outputFrame);
    is->video_info[index]->video_eof = true;
    av_log(NULL, AV_LOG_INFO, "video_thread end %d\n", index);
    is->video_info[index]->video_fin = true;
    return;
}

bool Converter::Configure_VideoFilter(AVFilterContext **filt_in, AVFilterContext **filt_out, AVFrame *frame, AVFilterGraph *graph, const VideoStreamInfo *video)
{
    AVFilterContext *filt_scale = NULL;
    AVFilterContext *filt_scale2 = NULL;
    AVFilterContext *filt_pad = NULL;
    AVFilterContext *filt_deint = NULL;
    AVFilterContext *filt_input, *filt_output;
    char args[256];
    
    snprintf(args, sizeof(args),
             "video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/%d",
             frame->width, frame->height, frame->format,
             video->video_st->time_base.num, video->video_st->time_base.den,
             video->video_st->codecpar->sample_aspect_ratio.num, FFMAX(video->video_st->codecpar->sample_aspect_ratio.den, 1));
    AVRational fr = av_guess_frame_rate(pFormatCtx, video->video_st, NULL);
    if (fr.num && fr.den)
        av_strlcatf(args, sizeof(args), ":frame_rate=%d/%d", fr.num, fr.den);
    
    if (avfilter_graph_create_filter(
                                     filt_in,
                                     avfilter_get_by_name("buffer"),
                                     "buffer",
                                     args,
                                     NULL,
                                     graph
                                     ) < 0)
        return false;
    if (avfilter_graph_create_filter(
                                     filt_out,
                                     avfilter_get_by_name("buffersink"),
                                     "buffersink",
                                     NULL,
                                     NULL,
                                     graph
                                     ) < 0)
        return false;
    filt_input = *filt_in;
    filt_output = *filt_out;
    if (video->deinterlace) {
        snprintf(args, sizeof(args), "mode=0:parity=-1:deint=1");
        if (avfilter_graph_create_filter(
                                         &filt_deint,
                                         avfilter_get_by_name("bwdif"),
                                         "deinterlace",
                                         args,
                                         NULL,
                                         graph
                                         ) < 0)
            return false;
        if (avfilter_link(filt_input, 0, filt_deint, 0) != 0)
            return false;
        filt_input = filt_deint;
    }
    {
        snprintf(args, sizeof(args), "iw*sar:ih");
        if (avfilter_graph_create_filter(
                                         &filt_scale2,
                                         avfilter_get_by_name("scale"),
                                         "scale2",
                                         args,
                                         NULL,
                                         graph
                                         ) < 0)
            return false;
        if (avfilter_link(filt_input, 0, filt_scale2, 0) != 0)
            return false;
        filt_input = filt_scale2;
    }
    {
        snprintf(args, sizeof(args), "iw*min(1920/iw\\,1080/ih):ih*min(1920/iw\\,1080/ih)");
        //snprintf(args, sizeof(args), "iw*min(1280/iw\\,720/ih):ih*min(1280/iw\\,720/ih)");
        if (avfilter_graph_create_filter(
                                         &filt_scale,
                                         avfilter_get_by_name("scale"),
                                         "scale",
                                         args,
                                         NULL,
                                         graph
                                         ) < 0)
            return false;
        if (avfilter_link(filt_input, 0, filt_scale, 0) != 0)
            return false;
        filt_input = filt_scale;
    }
    {
        snprintf(args, sizeof(args), "1920:1080:(ow-iw)/2:(oh-ih)/2");
        //snprintf(args, sizeof(args), "1280:720:(ow-iw)/2:(oh-ih)/2");
        if (avfilter_graph_create_filter(
                                         &filt_pad,
                                         avfilter_get_by_name("pad"),
                                         "pad",
                                         args,
                                         NULL,
                                         graph
                                         ) < 0)
            return false;
        if (avfilter_link(filt_input, 0, filt_pad, 0) != 0)
            return false;
        filt_input = filt_pad;
    }
    if (avfilter_link(filt_input, 0, filt_output, 0) != 0)
        return false;
    return (avfilter_graph_config(graph, NULL) >= 0);
}

static inline
int cmp_audio_fmts(enum AVSampleFormat fmt1, int64_t channel_count1,
                   enum AVSampleFormat fmt2, int64_t channel_count2)
{
    /* If channel count == 1, planar and non-planar formats are the same */
    if (channel_count1 == 1 && channel_count2 == 1)
        return av_get_packed_sample_fmt(fmt1) != av_get_packed_sample_fmt(fmt2);
    else
        return channel_count1 != channel_count2 || fmt1 != fmt2;
}

void audio_thread(Converter *is, int index)
{
    av_log(NULL, AV_LOG_INFO, "audio_thread %d start\n", index);
    auto encode = ((struct convert_param *)is->param)->encode_sound;
    auto stream = ((struct convert_param *)is->param)->stream;
    auto duration = ((struct convert_param *)is->param)->duration;
    AVCodecContext *aCodecCtx = is->audio_info[index]->audio_ctx.get();
    AVPacket pkt = { 0 }, *inpkt = &pkt;
    AVFrame audio_frame_in = { 0 }, *inframe = &audio_frame_in;
    AVFrame audio_frame_out = { 0 };
    std::shared_ptr<AVFilterGraph> graph(avfilter_graph_alloc(), [](AVFilterGraph *ptr) { avfilter_graph_free(&ptr); });
    AVFilterContext *filt_out = NULL, *filt_in = NULL;
    uint8_t  *silence_buf = NULL;
    int silence_buflen = 0;

    AVChannelLayout audio_out_channel_layout;
    av_channel_layout_default(&audio_out_channel_layout, 2);
    int audio_out_sample_rate = 48000;
    
    int64_t delta_pts_t = AV_NOPTS_VALUE;
    double delta_pts = 0;

    while(true) {
        int ret;
        if (is->IsQuit()) break;
        if (inpkt) {
            if ((ret = is->audio_info[index]->audioq.get(inpkt, 1)) < 0) {
                av_log(NULL, AV_LOG_INFO, "audio %d Quit\n", index);
                is->audio_info[index]->audio_eof = is->audio_eof_enum::eof;
                goto quit_audio;
            }
            if (is->audio_info[index]->audio_eof == is->audio_eof_enum::playing && ret == 0) {
                continue;
            }
            if(inpkt->data) {
                if (strcmp((char *)inpkt->data, FLUSH_STR) == 0) {
                    av_log(NULL, AV_LOG_INFO, "audio %d buffer flush\n", index);
                    avcodec_flush_buffers(aCodecCtx);
                    pkt = { 0 };
                    inpkt = &pkt;
                    inframe = &audio_frame_in;
                    continue;
                }
                if (strcmp((char *)inpkt->data, ABORT_STR) == 0) {
                    av_log(NULL, AV_LOG_INFO, "audio %d buffer ABORT\n", index);
                    is->audio_info[index]->audio_eof = is->audio_eof_enum::eof;
                    goto quit_audio;
                }
                if (strcmp((char *)inpkt->data, EOF_STR) == 0) {
                    av_log(NULL, AV_LOG_INFO, "audio %d buffer EOF\n", index);
                    is->audio_info[index]->audio_eof = is->audio_eof_enum::input_eof;
                }
            }
        }
        if (is->audio_info[index]->audio_eof >= is->audio_eof_enum::input_eof) {
            inpkt = NULL;
            if (is->audio_info[index]->audio_eof == is->audio_eof_enum::output_eof) {
                is->audio_info[index]->audio_eof = is->audio_eof_enum::eof;
                av_log(NULL, AV_LOG_INFO, "audio %d EOF\n", index);
                goto quit_audio;
            }
        }
        
        // send packet to codec context
        ret = avcodec_send_packet(aCodecCtx, inpkt);
        if (ret >= 0 || (is->audio_info[index]->audio_eof == is->audio_eof_enum::input_eof && ret == AVERROR_EOF)) {
            if (inpkt) av_packet_unref(inpkt);
            
            // Decode audio frame
            while ((ret = avcodec_receive_frame(aCodecCtx, inframe)) >= 0 || ret == AVERROR_EOF) {
                if (ret == AVERROR_EOF)
                    inframe = NULL;
                
                if (inframe) {
                    printf("ch %d %d\n", index, inframe->sample_rate);
                    auto dec_channel_layout = inframe->ch_layout;
                    if (dec_channel_layout.nb_channels == 0)
                        av_channel_layout_default(&dec_channel_layout, 2);
                    bool reconfigure =
                    cmp_audio_fmts(is->audio_info[index]->audio_filter_src.fmt, is->audio_info[index]->audio_filter_src.channels,
                                   (enum AVSampleFormat)inframe->format, inframe->ch_layout.nb_channels) ||
                    av_channel_layout_compare(&is->audio_info[index]->audio_filter_src.channel_layout, &dec_channel_layout) != 0 ||
                    is->audio_info[index]->audio_filter_src.freq != inframe->sample_rate;
                    
                    if (reconfigure) {
                        av_log(NULL, AV_LOG_INFO, "audio %d reconfigure\n", index);
                        is->audio_info[index]->audio_filter_src.fmt = (enum AVSampleFormat)inframe->format;
                        is->audio_info[index]->audio_filter_src.channels = inframe->ch_layout.nb_channels;
                        is->audio_info[index]->audio_filter_src.channel_layout = dec_channel_layout;
                        is->audio_info[index]->audio_filter_src.freq = inframe->sample_rate;
                        
                        graph = std::shared_ptr<AVFilterGraph>(avfilter_graph_alloc(), [](AVFilterGraph *ptr) { avfilter_graph_free(&ptr); });
                        if (!is->configure_audio_filters(&filt_in, &filt_out, graph.get(), is->audio_info[index]->audio_filter_src, audio_out_sample_rate, audio_out_channel_layout))
                            goto quit_audio;
                    }
                }
                
                if (!filt_in || !filt_out)
                    goto quit_audio;
                
                if (av_buffersrc_add_frame(filt_in, inframe) < 0) {
                    av_log(NULL, AV_LOG_INFO, "audio %d av_buffersrc_add_frame() failed\n", index);
                    goto quit_audio;
                }
                
                if (inframe) av_frame_unref(inframe);
                while ((ret = av_buffersink_get_frame(filt_out, &audio_frame_out)) >= 0) {
                    is->audio_info[index]->absent = false;
                    
                    float *audio_buf = (float *)audio_frame_out.data[0];
                    int out_samples = audio_frame_out.nb_samples;
                    int out_size = sizeof(float) * out_samples * audio_out_channel_layout.nb_channels;
                    int64_t pts_t0 = audio_frame_out.best_effort_timestamp;
                    double pts = -1;
                    if (pts_t0 != AV_NOPTS_VALUE) {
                        if(is->audio_info[index]->audio_start_pts != AV_NOPTS_VALUE && is->audio_info[index]->audio_start_pts > 0x1FFFFFFFF && pts_t0 < is->audio_info[index]->audio_start_pts) {
                            av_log(NULL, AV_LOG_INFO, "audio %d pts wrap-around %lld->%lld\n", index, is->audio_info[index]->audio_start_pts, pts_t0);

                            pts_t0 += 0x1FFFFFFFF;
                        }
                        while(is->main_video < 0) {
                            if(is->IsQuit()) goto quit_audio;
                            av_usleep(10*1000);
                        }
                        // wait video
                        while(isnan(is->video_info[is->main_video]->video_clock_start)) {
                            if(is->IsQuit()) goto quit_audio;
                            av_usleep(10*1000);
                        }
                        if(is->video_info[is->main_video]->video_start_pts != AV_NOPTS_VALUE && is->video_info[is->main_video]->video_start_pts > 0x1FFFFFFFF && pts_t0 < is->video_info[is->main_video]->video_start_pts - 0x1FFFFFFF) {
                            pts_t0 += 0x1FFFFFFFF;
                        }
                        av_log(NULL, AV_LOG_INFO, "audio %d pts %lld\n", index, pts_t0);
                        pts = av_q2d(is->audio_info[index]->audio_st->time_base)*pts_t0;
                        av_log(NULL, AV_LOG_INFO, "audio %d clock %f\n", index, pts);
                        
                        pts -= is->video_info[is->main_video]->video_clock_start;
                        av_log(NULL, AV_LOG_INFO, "audio %d sync clock %f\n", index, pts);
                        
                        if(isnan(is->audio_info[index]->audio_clock_start)) {
                            av_log(NULL, AV_LOG_INFO, "set audio %d start %f, %lld\n", index, pts, pts_t0);
                            is->audio_info[index]->audio_clock_start = pts;
                            is->audio_info[index]->audio_start_pts = pts_t0;
                        }
                        if(is->audio_info[index]->audio_last_pts_t != AV_NOPTS_VALUE) {
                            delta_pts_t = pts_t0 - is->audio_info[index]->audio_last_pts_t;
                            delta_pts = av_q2d(is->audio_info[index]->audio_st->time_base)*delta_pts_t;
                        }
                        else if (pts >= 0) {
                            delta_pts_t = pts / av_q2d(is->audio_info[index]->audio_st->time_base);
                            delta_pts = pts;
                        }
                        else {
                            av_frame_unref(&audio_frame_out);
                            av_log(NULL, AV_LOG_INFO, "audio %d pts %f, %lld < 0 skip\n", index, pts, pts_t0);
                            continue;
                        }
                    }
                    else {
                        pts = std::nan("");
                        delta_pts_t = 0;
                        delta_pts = 0;
                    }
                    av_log(NULL, AV_LOG_INFO, "audio %d pts %f, %lld\n", index, pts, pts_t0);
                    
                    if (!isnan(duration) && pts > duration) {
                        is->Quit();
                    }
                    
                    if (delta_pts > 20) {
                        av_log(NULL, AV_LOG_INFO, "audio %d delta %f > 20s\n", index, delta_pts);
                        delta_pts = 20;
                        delta_pts_t = av_rescale_q(20, av_make_q(1,1), is->audio_info[index]->audio_st->time_base);
                    }
                    
                    auto delta_sample = av_rescale_q(delta_pts_t, is->audio_info[index]->audio_st->time_base, av_make_q(1, audio_out_sample_rate));
                    av_log(NULL, AV_LOG_INFO, "audio %d delta sample %lld\n", index, delta_sample);
                    
                    is->audio_info[index]->present = true;

                    if (!__builtin_isfinite(pts)) {
                        is->audio_info[index]->frame_count += out_samples;

                        encode(stream, (double)is->audio_info[index]->frame_count / audio_out_sample_rate, (uint8_t *)audio_buf, out_size, index);

                        av_frame_unref(&audio_frame_out);
                        continue;
                    }
                    if(delta_sample + out_samples < 0) {
                        av_log(NULL, AV_LOG_INFO, "audio %d skip\n", index);
                        av_frame_unref(&audio_frame_out);
                        continue;
                    }
                    if (abs(delta_sample) < 8196) {
                        pts += (double)(out_samples) / audio_out_sample_rate;
                        is->audio_info[index]->frame_count += out_samples;

                        is->audio_info[index]->audio_last_pts_t = pts_t0;
                        is->audio_info[index]->audio_last_pts = pts;

                        av_log(NULL, AV_LOG_INFO, "audio %d last pts %lld\n", index, pts_t0);

                        encode(stream, (double)is->audio_info[index]->frame_count / audio_out_sample_rate, (uint8_t *)audio_buf, out_size, index);
                    }
                    else {
                        if(delta_sample < 0) {
                            av_log(NULL, AV_LOG_INFO, "audio %d 0 delta %lld < 0\n", index, delta_sample);

                            int offset = int(-delta_sample);
                            int fix_out_size = sizeof(float) * int(out_samples+delta_sample) * audio_out_channel_layout.nb_channels;
                            pts += (double)(out_samples+delta_sample) / audio_out_sample_rate;
                            is->audio_info[index]->frame_count += out_samples+delta_sample;
                            
                            is->audio_info[index]->audio_last_pts_t = pts_t0;
                            is->audio_info[index]->audio_last_pts = pts;
                            av_log(NULL, AV_LOG_INFO, "audio %d last pts %lld\n", index, pts_t0);

                            encode(stream, (double)is->audio_info[index]->frame_count / audio_out_sample_rate, (uint8_t *)&audio_buf[offset*audio_out_channel_layout.nb_channels], fix_out_size, index);
                        }
                        else {
                            av_log(NULL, AV_LOG_INFO, "audio %d 0 delta %lld > 0\n", index, delta_sample);
                            
                            int pad_size = sizeof(float) * int(delta_sample) * audio_out_channel_layout.nb_channels;
                            if (silence_buflen < pad_size) {
                                delete [] silence_buf;
                                silence_buf = new uint8_t[pad_size];
                                silence_buflen = pad_size;
                                memset(silence_buf, 0, pad_size);
                            }
                            
                            pts += (double)(delta_sample) / audio_out_sample_rate;
                            is->audio_info[index]->frame_count += delta_sample;
                            encode(stream, (double)is->audio_info[index]->frame_count / audio_out_sample_rate, silence_buf, pad_size, index);

                            av_log(NULL, AV_LOG_INFO, "audio %d silence pad %lld\n", index, delta_sample);

                            pts += (double)(out_samples) / audio_out_sample_rate;
                            is->audio_info[index]->frame_count += out_samples;
                            
                            is->audio_info[index]->audio_last_pts_t = pts_t0;
                            is->audio_info[index]->audio_last_pts = pts;

                            av_log(NULL, AV_LOG_INFO, "audio %d last pts %lld\n", index, pts_t0);

                            encode(stream, (double)is->audio_info[index]->frame_count / audio_out_sample_rate, (uint8_t *)audio_buf, out_size, index);
                        }
                    }
                    av_frame_unref(&audio_frame_out);

                    printf("%d,%f,%f,%lld\n", index, (double)is->audio_info[index]->frame_count / audio_out_sample_rate, pts, pts_t0);
                    
                    // check other audio
                    if(is->audio_info[index]->main_audio) {
                        for(int i = 0; i < is->audio_info.size(); i++) {
                            if(i == index) continue;
                           
                            if(is->audio_info[i]->absent) {
                                // sync main audio and output same content
                                is->audio_info[i]->audio_last_pts_t = is->audio_info[index]->audio_last_pts_t;
                                is->audio_info[i]->audio_clock_start = is->audio_info[index]->audio_clock_start;
                                is->audio_info[i]->audio_start_pts = is->audio_info[index]->audio_start_pts;

                                if (silence_buflen < out_size) {
                                    delete [] silence_buf;
                                    silence_buf = new uint8_t[out_size];
                                    silence_buflen = out_size;
                                    memset(silence_buf, 0, sizeof(float) * out_samples * audio_out_channel_layout.nb_channels);
                                }
                                is->audio_info[i]->frame_count += out_samples;
                                
                                encode(stream, (double)is->audio_info[i]->frame_count / audio_out_sample_rate, silence_buf, out_size, i);
                                printf("%d,%f,silence\n", i, (double)is->audio_info[i]->frame_count / audio_out_sample_rate);
                            }
                        }
                    }
                }//while(av_buffersink_get_frame)
                
                if (ret == AVERROR_EOF) {
                    is->audio_info[index]->audio_eof = is->audio_eof_enum::output_eof;
                    av_log(NULL, AV_LOG_INFO, "audio %d output EOF\n", index);
                }
                
                if(!inframe) {
                    goto quit_audio;
                }
            }//while(avcodec_receive_frame)
        } //if (avcodec_send_packet)
        else {
            if(inpkt) av_packet_unref(inpkt);
        }
        
        if (is->IsQuit()) {
            is->audio_info[index]->audio_eof = is->audio_eof_enum::eof;
            goto quit_audio;
        }
    }//while(true)
quit_audio:
    av_log(NULL, AV_LOG_INFO, "audio_thread loop %d end\n", index);
    is->audio_info[index]->absent = true;
    is->audio_info[index]->audioq.clear();
    delete [] silence_buf;
    is->audio_info[index]->audio_eof = is->audio_eof_enum::eof;
    av_log(NULL, AV_LOG_INFO, "audio_thread %d end\n", index);
    is->audio_info[index]->audio_fin = true;
    return;
}

void audio_dummy_thread(Converter *is)
{
    int index = 0;
    av_log(NULL, AV_LOG_INFO, "audio_thread %d start\n", index);
    auto encode = ((struct convert_param *)is->param)->encode_sound;
    auto stream = ((struct convert_param *)is->param)->stream;
    uint8_t  *silence_buf = NULL;
    int silence_buflen = 0;

    int audio_out_channels = 2;
    int audio_out_sample_rate = 48000;
    double pts = 0;
    uint64_t frame_count = 0;
    
    while(is->main_video < 0) {
        if(is->IsQuit()) goto quit_audio;
        av_usleep(10*1000);
    }
    // wait video
    while(isnan(is->video_info[is->main_video]->video_clock_start)) {
        if(is->IsQuit()) goto quit_audio;
        av_usleep(10*1000);
    }

    while(true) {
        if (is->IsQuit()) break;
        
        int sample_count = 4096;
        int pad_size = sizeof(float) * sample_count * audio_out_channels;
        if (silence_buflen < pad_size) {
            delete [] silence_buf;
            silence_buf = new uint8_t[pad_size];
            silence_buflen = pad_size;
            memset(silence_buf, 0, pad_size);
        }
        
        pts += (double)(sample_count) / audio_out_sample_rate;
        frame_count += sample_count;
        encode(stream, (double)frame_count / audio_out_sample_rate, silence_buf, pad_size, index);

        av_log(NULL, AV_LOG_INFO, "audio %d silence %d\n", index, sample_count);
    }//while(true)
quit_audio:
    av_log(NULL, AV_LOG_INFO, "audio_thread loop %d end\n", index);
    delete [] silence_buf;
    av_log(NULL, AV_LOG_INFO, "audio_thread %d end\n", index);
    is->audio_info[index]->audio_fin = true;
    return;
}

bool Converter::configure_audio_filters(AVFilterContext **filt_in, AVFilterContext **filt_out, AVFilterGraph *graph, const AudioParams &audio_filter_src, int audio_out_sample_rate, const AVChannelLayout &audio_out_channel_layout)
{
    char asrc_args[256] = { 0 };
    AVFilterContext *filt_asrc = NULL, *filt_asink = NULL;
    AVBPrint bp;

    if (!graph) return false;
    
    av_bprint_init(&bp, 0, AV_BPRINT_SIZE_AUTOMATIC);
    av_channel_layout_describe_bprint(&audio_filter_src.channel_layout, &bp);

    snprintf(asrc_args, sizeof(asrc_args),
                   "sample_rate=%d:sample_fmt=%s:time_base=%d/%d:channel_layout=%s",
                   audio_filter_src.freq, av_get_sample_fmt_name(audio_filter_src.fmt),
                   1, audio_filter_src.freq, bp.str);

    if (avfilter_graph_create_filter(&filt_asrc,
                                     avfilter_get_by_name("abuffer"), "ffconvert_abuffer",
                                     asrc_args, NULL, graph) < 0)
        return false;
    
    filt_asink = avfilter_graph_alloc_filter(graph, avfilter_get_by_name("abuffersink"),
                                                 "ffconvert_abuffersink");
    if (!filt_asink) {
        return false;
    }

    if(av_opt_set(filt_asink, "sample_formats", "flt", AV_OPT_SEARCH_CHILDREN) < 0)
        return false;
    
    if(av_opt_set_array(filt_asink, "channel_layouts", AV_OPT_SEARCH_CHILDREN,
                        0, 1, AV_OPT_TYPE_CHLAYOUT, &audio_out_channel_layout) < 0)
        return false;

    if(av_opt_set_array(filt_asink, "samplerates", AV_OPT_SEARCH_CHILDREN,
                        0, 1, AV_OPT_TYPE_INT, &audio_out_sample_rate) < 0)
        return false;

    if(avfilter_init_dict(filt_asink, NULL) < 0)
        return false;
    
    if(avfilter_link(filt_asrc, 0, filt_asink, 0) < 0)
        return false;
    
    if(avfilter_graph_config(graph, NULL) < 0)
        return false;

    *filt_in = filt_asrc;
    *filt_out = filt_asink;
    av_bprint_finalize(&bp, NULL);
    return true;
}

struct sub_info {
    double start;
    double end;
    std::string text;
    bool ass;
    int ch;
};

int subtitle_thread(Converter *is, int index)
{
    av_log(NULL, AV_LOG_INFO, "subtitle_thread %d start\n", index);
    auto encode = ((struct convert_param *)is->param)->encode_text;
    auto stream = ((struct convert_param *)is->param)->stream;
    AVPacket packet = { 0 };
    std::shared_ptr<SwsContext> sub_convert_ctx;
    int64_t old_serial = 0;
    sub_info prev_sub;

    while(is->main_video < 0) {
        if(is->IsQuit())
            break;
        av_usleep(10*1000);
    }

    is->subtitle_info[index]->subpictq_active_serial = av_gettime();
    while (!is->IsQuit()) {
        AVCodecContext *subtitle_ctx = is->subtitle_info[index]->subtitle_ctx.get();
        if (is->subtitle_info[index]->subtitleq.get(&packet, 1) < 0) {
            // means we quit getting packets
            av_log(NULL, AV_LOG_INFO, "subtitle Quit %d\n", index);
            break;
        }
    retry:
        if(packet.data) {
            if (strcmp((char *)packet.data, FLUSH_STR) == 0) {
                av_log(NULL, AV_LOG_INFO, "subtitle buffer flush %d\n", index);
                avcodec_flush_buffers(subtitle_ctx);
                old_serial = 0;
                packet = { 0 };
                continue;
            }
            if (strcmp((char *)packet.data, ABORT_STR) == 0) {
                av_log(NULL, AV_LOG_INFO, "subtitle buffer ABORT %d\n", index);
                packet = { 0 };
                break;
            }
            if (strcmp((char *)packet.data, EOF_STR) == 0) {
                av_log(NULL, AV_LOG_INFO, "subtitle buffer EOF %d\n", index);
                packet = { 0 };
                while (!is->IsQuit() && is->subtitle_info[index]->subtitleq.get(&packet, 0) == 0)
                    av_usleep(100*1000);
                if (is->IsQuit()) break;
                goto retry;
            }
        }
        int got_frame = 0;
        int ret;
        AVSubtitle sub;
        double pts = 0;
        pts = packet.pts * av_q2d(is->subtitle_timebase);
        if ((ret = avcodec_decode_subtitle2(subtitle_ctx, &sub, &got_frame, &packet)) < 0) {
            av_packet_unref(&packet);
            char buf[AV_ERROR_MAX_STRING_SIZE];
            char *errstr = av_make_error_string(buf, AV_ERROR_MAX_STRING_SIZE, ret);
            av_log(NULL, AV_LOG_ERROR, "error avcodec_decode_subtitle2() %d %s\n", ret, errstr);
            return -1;
        }
        av_packet_unref(&packet);
        if (got_frame == 0) continue;

        // av_log(NULL, AV_LOG_INFO, "subtitle pts %lld\n", sub.pts);
        if (sub.pts != AV_NOPTS_VALUE) {
            pts = sub.pts * av_q2d(AV_TIME_BASE_Q);
        }
        // av_log(NULL, AV_LOG_INFO, "subtitle time %f\n", pts);
        if(sub.format == 0 && is->main_subtitle == index) {
            std::shared_ptr<SubtitlePicture> sp(new SubtitlePicture);
            sp->pts = pts;
            sp->serial = av_gettime();
            while (old_serial >= sp->serial) sp->serial++;
            old_serial = sp->serial;
            sp->sub = sub;
            sp->subw = subtitle_ctx->width ? subtitle_ctx->width : is->video_info[is->main_video]->video_ctx->width;
            sp->subh = subtitle_ctx->height ? subtitle_ctx->height : is->video_info[is->main_video]->video_ctx->height;
            for (size_t i = 0; i < sub.num_rects; i++) {
                int width = sub.rects[i]->w * is->video_info[is->main_video]->video_aspect;
                uint8_t *data[4];
                int linesize[4];
                if (av_image_alloc(data, linesize, width, sub.rects[i]->h, AV_PIX_FMT_BGRA, 16) < 0) {
                    av_log(NULL, AV_LOG_FATAL, "Cannot allocate subtitle data\n");
                    return -1;
                }
                auto sub_convert_ctx = sws_getCachedContext(NULL,
                                                            sub.rects[i]->w, sub.rects[i]->h, AV_PIX_FMT_PAL8,
                                                            width, sub.rects[i]->h, AV_PIX_FMT_BGRA,
                                                            SWS_BICUBIC, NULL, NULL, NULL);
                if (!sub_convert_ctx) {
                    av_log(NULL, AV_LOG_FATAL, "Cannot initialize the sub conversion context\n");
                    return -1;
                }
                sws_scale(sub_convert_ctx,
                    sub.rects[i]->data, sub.rects[i]->linesize,
                    0, sub.rects[i]->h, data, linesize);
                sws_freeContext(sub_convert_ctx);

                av_freep(&sub.rects[i]->data[0]);
                av_freep(&sub.rects[i]->data[1]);
                av_freep(&sub.rects[i]->data[2]);
                av_freep(&sub.rects[i]->data[3]);
                sp->sub.rects[i]->w = width;
                sp->sub.rects[i]->data[0] = data[0];
                sp->sub.rects[i]->data[1] = data[1];
                sp->sub.rects[i]->data[2] = data[2];
                sp->sub.rects[i]->data[3] = data[3];
                sp->sub.rects[i]->linesize[0] = linesize[0];
                sp->sub.rects[i]->linesize[1] = linesize[1];
                sp->sub.rects[i]->linesize[2] = linesize[2];
                sp->sub.rects[i]->linesize[3] = linesize[3];
            }
            is->subtitle_info[index]->subpictq.put(sp);
        }
        else if(sub.format == 1){
            bool ass = false;
            std::ostringstream os;
            for (int i = 0; i < sub.num_rects; i++) {
                if (sub.rects[i]->text) {
                    os << sub.rects[i]->text << std::endl;
                }
                if (sub.rects[i]->ass) {
                    os << sub.rects[i]->ass << std::endl;
                    ass = true;
                }
            }
            while (isnan(is->video_info[is->main_video]->video_clock_start)) {
                if(is->IsQuit())
                    break;
                av_usleep(100*1000);
            }
            double vst = is->video_info[is->main_video]->video_clock_start;
            if(isnan(vst))
                vst = 0;
            if(prev_sub.end < 0) {
                prev_sub.end = pts - vst;
                encode(stream, prev_sub.start, prev_sub.end, prev_sub.text.c_str(), prev_sub.ass, prev_sub.ch);
                prev_sub = { 0 };
            }
            if(sub.end_display_time == 0xFFFFFFFF || sub.end_display_time == 0) {
                double st = pts + (double)sub.start_display_time / 1000 - vst;
                prev_sub = { st, -1, os.str(), ass, is->subtitle_info[index]->textIndex };
            }
            else {
                double st = pts + (double)sub.start_display_time / 1000 - vst;
                double et = pts + (double)sub.end_display_time / 1000 - vst;
                encode(stream, st, et, os.str().c_str(), ass?1:0, is->subtitle_info[index]->textIndex);
            }
            avsubtitle_free(&sub);
        }
        else {
            avsubtitle_free(&sub);
        }
    }
    av_log(NULL, AV_LOG_INFO, "subtitle thread %d end\n", index);
    return 0;
}

void Converter::subtitle_overlay(AVFrame &output, double pts)
{
    if(main_subtitle < 0) return;
    auto subtitle = subtitle_info[main_subtitle];
    
    std::shared_ptr<SubtitlePicture> sp;
    if (subtitle->subpictq.peek(sp) == 0) {
        // skip to current present subtitle
        while (sp->serial < subtitle->subpictq_active_serial && subtitle->subpictq.get(sp) == 0)
            ;
        if (sp->serial < subtitle->subpictq_active_serial)
            return;
        
        if(sp->sub.end_display_time == 0xffffffff || sp->sub.end_display_time == 0) {
            std::shared_ptr<SubtitlePicture> sp2;
            if(subtitle->subpictq.peek2(sp2) == 0) {
                if(pts > sp2->pts) {
                    subtitle->subpictq.get(sp);
                    sp = sp2;
                }
            }
            else {
                if(pts > sp->pts + 5) {
                    subtitle->subpictq.get(sp);
                }
            }
        }
        else {
            if (pts > sp->pts + (double)sp->sub.end_display_time / 1000) {
                subtitle->subpictq.get(sp);
            }
        }
        printf("video %f, cc %f %d %d\n", pts, sp->pts, sp->sub.start_display_time, sp->sub.end_display_time);

        bool show = pts <= sp->pts + (double)sp->sub.end_display_time / 1000 &&
                    pts >= sp->pts + (double)sp->sub.start_display_time / 1000;
        if(sp->sub.end_display_time == 0xffffffff || sp->sub.end_display_time == 0) {
            show = pts >= sp->pts + (double)sp->sub.start_display_time / 1000;
        }
        
        if (show) {
            if (sp->sub.format == 0) {
                for (int i = 0; i < sp->sub.num_rects; i++) {
                    int s_w = sp->sub.rects[i]->w;
                    int s_h = sp->sub.rects[i]->h;
                    int s_x = sp->sub.rects[i]->x;
                    int s_y = sp->sub.rects[i]->y;
                    for(int y = s_y, sy = 0; y < output.height && sy < s_h; y++, sy++){
                        uint8_t *sublp = sp->sub.rects[i]->data[0];
                        uint8_t *displyp = output.data[0];
                        uint8_t *displup = output.data[1];
                        uint8_t *displvp = output.data[2];
                        sublp = sublp + sy * sp->sub.rects[i]->linesize[0];
                        displyp = displyp + y * output.linesize[0];
                        displup = displup + y / 2 * output.linesize[1];
                        displvp = displvp + y / 2 * output.linesize[2];
                        for(int x = s_x, sx = 0; x < output.width && sx < s_w; x++, sx++){
                            uint8_t *subp = &sublp[sx * 4];
                            double dispy = displyp[x] / 255.0;
                            double dispu = (displup[x/2] - 128.0) / 255.0;
                            double dispv = (displvp[x/2] - 128.0) / 255.0;
                            double a = subp[3] / 255.0;
                            double r = subp[2] / 255.0;
                            double g = subp[1] / 255.0;
                            double b = subp[0] / 255.0;
                            double r1 = 1.0 * dispy                 + 1.402 * dispv;
                            double g1 = 1.0 * dispy - 0.344 * dispu - 0.714 * dispv;
                            double b1 = 1.0 * dispy + 1.772 * dispu;
                            double r2 = r1*(1-a) + r*a;
                            double g2 = g1*(1-a) + g*a;
                            double b2 = b1*(1-a) + b*a;
                            double Y =  0.299 * r2 + 0.587 * g2 + 0.114 * b2;
                            double U = -0.169 * r2 - 0.331 * g2 + 0.500 * b2;
                            double V =  0.500 * r2 - 0.419 * g2 - 0.081 * b2;
                            displyp[x] = Y * 255;
                            if (y % 2 == 1 && x % 2 == 1) {
                                displup[x/2] = U * 255 + 128;
                                displvp[x/2] = V * 255 + 128;
                            }
                        }
                    }
                }
            }
        }
    }
}

int Converter::stream_component_open(int stream_index)
{
    std::shared_ptr<AVCodecContext> codecCtx;
    const AVCodec *codec;

    if (stream_index < 0 || (unsigned)stream_index >= pFormatCtx->nb_streams) {
        return -1;
    }

    codec = avcodec_find_decoder(pFormatCtx->streams[stream_index]->codecpar->codec_id);
    if (!codec) {
        av_log(NULL, AV_LOG_PANIC, "Unsupported codec!\n");
        return -1;
    }
    
    codecCtx = std::shared_ptr<AVCodecContext>(avcodec_alloc_context3(codec), [](AVCodecContext *ptr) {avcodec_free_context(&ptr); });
    if (avcodec_parameters_to_context(codecCtx.get(), pFormatCtx->streams[stream_index]->codecpar) < 0) {
        av_log(NULL, AV_LOG_PANIC, "Couldn't copy codec parameter to codec context\n");
        return -1;
    }
    codecCtx->time_base = pFormatCtx->streams[stream_index]->time_base;
    
    AVDictionary *opts = NULL;
    av_dict_set(&opts, "threads", "auto", 0);
    if(codecCtx->codec_id == AV_CODEC_ID_ARIB_CAPTION) {
        if(arib_to_text) {
            av_dict_set_int(&opts, "sub_type", SUBTITLE_TEXT, 0);
        }
        else {
            av_dict_set_int(&opts, "sub_type", SUBTITLE_BITMAP, 0);
        }
    }

    if (avcodec_open2(codecCtx.get(), codec, &opts) < 0) {
        av_log(NULL, AV_LOG_PANIC, "Unsupported codec!\n");
        return -1;
    }
    av_dict_free(&opts);
    
    AVDictionaryEntry *lang = av_dict_get(pFormatCtx->streams[stream_index]->metadata, "language", NULL,0);

    pFormatCtx->streams[stream_index]->discard = AVDISCARD_DEFAULT;
    switch (codecCtx->codec_type) {
        case AVMEDIA_TYPE_AUDIO:
        {
            std::shared_ptr<AudioStreamInfo> info(new AudioStreamInfo(this));
            info->audio_st = pFormatCtx->streams[stream_index];
            info->audio_ctx = codecCtx;
            info->audio_eof = playing;
            if(lang) {
                info->language = lang->value;
            }
            else {
                info->language = "und";
            }
            audio_info.push_back(info);
            
            audio_thread.push_back(std::thread(::audio_thread, this, audio_info.size()-1));
        }
            break;
        case AVMEDIA_TYPE_VIDEO:
        {
            std::shared_ptr<VideoStreamInfo> info(new VideoStreamInfo(this));
            info->video_st = pFormatCtx->streams[stream_index];
            info->video_ctx = codecCtx;
            if(lang) {
                info->language = lang->value;
            }
            else {
                info->language = "und";
            }
            info->video_SAR = info->video_ctx->sample_aspect_ratio;
            double aspect_ratio = 0;
            if (info->video_ctx->sample_aspect_ratio.num == 0) {
                aspect_ratio = 0;
            }
            else {
                aspect_ratio = av_q2d(info->video_ctx->sample_aspect_ratio) *
                info->video_ctx->width / info->video_ctx->height;
            }
            if (aspect_ratio <= 0.0) {
                aspect_ratio = (double)info->video_ctx->width /
                (double)info->video_ctx->height;
            }
            info->video_height = codecCtx->height;
            info->video_width = ((int)rint(info->video_height * aspect_ratio)) & ~1;
            info->video_srcheight = codecCtx->height;
            info->video_srcwidth = codecCtx->width;
            info->video_eof = false;
            video_info.push_back(info);
            
            video_thread.push_back(std::thread(::video_thread, this, video_info.size()-1));
        }
            break;
        case AVMEDIA_TYPE_SUBTITLE:
        {
            std::shared_ptr<SubtitleStreamInfo> info(new SubtitleStreamInfo(this));
            info->subtitle_st = pFormatCtx->streams[stream_index];
            info->subtitle_ctx = codecCtx;
            if(lang) {
                info->language = lang->value;
            }
            else {
                info->language = "und";
            }
            subtitle_info.push_back(info);

            subtitle_thread.push_back(std::thread(::subtitle_thread, this, subtitle_info.size()-1));
        }
            break;
        default:
            pFormatCtx->streams[stream_index]->discard = AVDISCARD_ALL;
            break;
    }
    return 0;
}

void Converter::stream_component_close(int stream_index)
{
    AVFormatContext *ic = pFormatCtx;
    
    if (stream_index < 0 || (unsigned int)stream_index >= ic->nb_streams)
        return;
    
    AVCodecParameters *codecpar = ic->streams[stream_index]->codecpar;
    
    switch (codecpar->codec_type) {
        case AVMEDIA_TYPE_AUDIO:
        {
            for(int i = 0; i < audioStream.size(); i++) {
                if(stream_index == audioStream[i]) {
                    audio_info[i]->audioq.AbortQueue();
                    if(audio_thread[i].joinable())
                        audio_thread[i].join();
                    break;
                }
            }
            break;
        }
        case AVMEDIA_TYPE_VIDEO:
            for(int i = 0; i < videoStream.size(); i++) {
                if(stream_index == videoStream[i]) {
                    video_info[i]->videoq.AbortQueue();
                    if(video_thread[i].joinable())
                        video_thread[i].join();
                    break;
                }
            }
            break;
        case AVMEDIA_TYPE_SUBTITLE:
            for(int i = 0; i < subtitleStream.size(); i++) {
                if(stream_index == subtitleStream[i]) {
                    subtitle_info[i]->subtitleq.AbortQueue();
                    if(subtitle_thread[i].joinable())
                        subtitle_thread[i].join();
                    break;
                }
            }
            break;
        default:
            break;
    }
    
    ic->streams[stream_index]->discard = AVDISCARD_ALL;
    switch (codecpar->codec_type) {
        case AVMEDIA_TYPE_AUDIO:
        {
            int index = -1;
            for(int i = 0; i < audioStream.size(); i++) {
                if(stream_index == audioStream[i]) {
                    index = i;
                    break;
                }
            }
            if (index >= 0){
                audioStream.erase(audioStream.begin() + index);
                audio_info.erase(audio_info.begin() + index);
                audio_thread.erase(audio_thread.begin() + index);
            }
            break;
        }
        case AVMEDIA_TYPE_VIDEO:
        {
            int index = -1;
            for(int i = 0; i < videoStream.size(); i++) {
                if(stream_index == videoStream[i]) {
                    index = i;
                    break;
                }
            }
            if (index >= 0){
                videoStream.erase(videoStream.begin() + index);
                video_info.erase(video_info.begin() + index);
                video_thread.erase(video_thread.begin() + index);
            }
            break;
        }
        case AVMEDIA_TYPE_SUBTITLE:
        {
            int index = -1;
            for(int i = 0; i < subtitleStream.size(); i++) {
                if(stream_index == subtitleStream[i]) {
                    index = i;
                    break;
                }
            }
            if (index >= 0){
                subtitleStream.erase(subtitleStream.begin() + index);
                subtitle_info.erase(subtitle_info.begin() + index);
                subtitle_thread.erase(subtitle_thread.begin() + index);
            }
            break;
        }
        default:
            break;
    }
}


void Converter::Quit()
{
    quit = true;
    for(auto video: video_info) {
        video->videoq.AbortQueue();
    }
    for(auto audio: audio_info) {
        audio->audioq.AbortQueue();
    }
    for(auto subtitle: subtitle_info) {
        subtitle->subtitleq.AbortQueue();
    }
}

bool Converter::IsQuit(bool pure)
{
    if(!pure && quit) return quit;
    bool isAllQuit = true;
    for(const auto &audio: audio_info) {
        if(audio->audio_fin) {
            continue;
        }
        if(audio->audio_eof != audio_eof_enum::eof) {
            isAllQuit = false;
            break;
        }
    }
    if(isAllQuit) {
        for(const auto &video: video_info) {
            if(video->video_fin) {
                continue;
            }
            if(!video->video_eof) {
                isAllQuit = false;
                break;
            }
        }
    }
    return isAllQuit;
}

void Converter::Finalize()
{
    Quit();
    
    // avtivate threads for exit
    if (audioStream.size() > 0) {
        for(auto &audio: audio_info){
            audio->audioq.AbortQueue();
        }
    }
    if (videoStream.size() > 0) {
        for(auto &video: video_info){
            video->videoq.AbortQueue();
        }
    }
    if (subtitleStream.size() > 0) {
        for(auto &subtitle: subtitle_info){
            subtitle->subtitleq.AbortQueue();
        }
    }
    // wait for exit threads
    if (parse_thread.joinable())
        parse_thread.join();
    for(auto &th: video_thread) {
        if(th.joinable())
            th.join();
    }
    for(auto &th: audio_thread) {
        if(th.joinable())
            th.join();
    }
    for(auto &th: subtitle_thread) {
        if(th.joinable())
            th.join();
    }
    
    for(auto &video: video_info){
        video->videoq.clear();
    }
    for(auto &audio: audio_info){
        audio->audioq.clear();
    }
    for(auto &subtitle: subtitle_info){
        subtitle->subtitleq.clear();
    }
}
