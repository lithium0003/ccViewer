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
    }
    
    void freeParam(struct convert_param * param)
    {
        printf("freeParam\n");
        delete (Converter *)param->converter;
    }
    
    int createParseThread(struct convert_param * param) {
        ((Converter *)param->converter)->parse_thread = std::thread(decode_thread, param);
        return 0;
    }
    
    int waitParseThread(struct convert_param * param) {
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
        if (desc != NULL) {
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
    
    // main decode loop
    av_log(NULL, AV_LOG_INFO, "decode_thread read loop\n");
    for (;;) {
        if (converter->IsQuit()) {
            goto finish;
        }
  
        if (converter->videoStream.size() > 0) {
            bool isFull = false;
            for(auto video: converter->video_info){
                if(video->videoq.size > MAX_VIDEOQ_SIZE) {
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
                if(audio->audioq.size > MAX_AUDIOQ_SIZE) {
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

        error = false;
        bool found = false;
        // Is this a packet from the video stream?
        for(int i = 0; i < converter->videoStream.size(); i++) {
            if (packet.stream_index == converter->videoStream[i]) {
                av_log(NULL, AV_LOG_INFO, "video packet %lld\n", packet_count);
                converter->video_info[i]->video_eof = false;
                converter->video_info[i]->videoq.put(&packet);
                video_last = packet_count;
                found = true;
            }
        }
        if (!found) {
            for(int i = 0; i < converter->subtitleStream.size(); i++) {
                if (packet.stream_index == converter->subtitleStream[i]) {
                    av_log(NULL, AV_LOG_INFO, "subtile packet %lld\n", packet_count);
                    converter->subtitle_info[i]->subtitleq.put(&packet);
                    found = true;
                }
            }
        }
        if (!found) {
            // sound stream id check
            bool main_packet = false;
            for(int i = 0; i < converter->audioStream.size(); i++) {
                if (packet.stream_index == converter->audioStream[i]) {
                    av_log(NULL, AV_LOG_INFO, "audio packet %lld\n", packet_count);
                    converter->audio_info[i]->audio_eof = Converter::audio_eof_enum::playing;
                    converter->audio_info[i]->absent = false;
                    converter->audio_info[i]->audioq.put(&packet);
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
        // release packet if not used
        if(!found) {
            av_packet_unref(&packet);
        }
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
    //outputFrame.format = AVPixelFormat::AV_PIX_FMT_YUYV422;
    outputFrame.format = AVPixelFormat::AV_PIX_FMT_BGRA;
    outputFrame.width = out_width;
    outputFrame.height = out_height;
    av_frame_get_buffer(&outputFrame, 32);
    double pts = 0;
    int64_t count = 0;

    while(is->main_video < 0) {
        if(is->IsQuit()) goto finish;
        av_usleep(10*1000);
    }
    while(is->main_audio < 0) {
        if(is->IsQuit()) goto finish;
        av_usleep(10*1000);
    }

    av_log(NULL, AV_LOG_INFO, "video_thread %d read loop\n", index);
    while (true) {
        if (is->IsQuit()) break;

        int key = 1;
        while(pts > is->audio_info[is->main_audio]->audio_last_pts) {
            if(is->IsQuit()) goto finish;
            av_usleep(10*1000);
        }
        pts = (double)(count++) / 30.0;
        encode(stream, pts, key, outputFrame.data[0], outputFrame.linesize[0], outputFrame.height);
    }
loopend:
    av_log(NULL, AV_LOG_INFO, "video_thread loop end %d\n", index);
    is->video_info[index]->videoq.clear();
    finish(stream);
finish:
    av_frame_unref(&outputFrame);
    is->video_info[index]->video_eof = true;
    av_log(NULL, AV_LOG_INFO, "video_thread end %d\n", index);
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
    //outputFrame.format = AVPixelFormat::AV_PIX_FMT_YUYV422;
    outputFrame.format = AVPixelFormat::AV_PIX_FMT_BGRA;
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
        
        if (packet.data == flush_pkt.data) {
            av_log(NULL, AV_LOG_INFO, "video buffer flush %d\n", index);
            avcodec_flush_buffers(video_ctx);
            packet = { 0 };
            inpkt = &packet;
            inframe = &frame1;
            is->video_info[index]->video_eof = false;
            continue;
        }
        if (packet.data == eof_pkt.data) {
            av_log(NULL, AV_LOG_INFO, "video buffer EOF %d\n", index);
            packet = { 0 };
            inpkt = NULL;
        }
        if (packet.data == abort_pkt.data) {
            av_log(NULL, AV_LOG_INFO, "video buffer ABORT %d\n", index);
            is->video_info[index]->video_eof = true;
            packet = { 0 };
            break;
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
                    
                    key = frame2.key_frame;
                    //printf("key2 %d\n", key);
                    sws_context = sws_getCachedContext(sws_context,
                                                       frame2.width, frame2.height,
                                                       (AVPixelFormat)frame2.format,
                                                       frame2.width, frame2.height,
                                                       AVPixelFormat::AV_PIX_FMT_BGRA,
                                                       SWS_BICUBLIN, NULL, NULL, NULL);
                    
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

                    is->subtitle_overlay(outputFrame, pts+is->video_info[index]->video_clock_start);
                    
                    encode(stream, pts, key, outputFrame.data[0], outputFrame.linesize[0], outputFrame.height);
                    is->video_info[index]->video_prev_pts = pts_t;

                    av_frame_unref(&frame2);
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
int64_t get_valid_channel_layout(int64_t channel_layout, int channels)
{
    if (channel_layout && av_get_channel_layout_nb_channels(channel_layout) == channels)
        return channel_layout;
    else
        return 0;
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

    int audio_out_channels = 2;
    int audio_out_sample_rate = 48000;
    
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
            if (inpkt->data == flush_pkt.data) {
                av_log(NULL, AV_LOG_INFO, "audio %d buffer flush\n", index);
                avcodec_flush_buffers(aCodecCtx);
                pkt = { 0 };
                inpkt = &pkt;
                inframe = &audio_frame_in;
                continue;
            }
            if (inpkt->data == eof_pkt.data) {
                av_log(NULL, AV_LOG_INFO, "audio %d buffer EOF\n", index);
                is->audio_info[index]->audio_eof = is->audio_eof_enum::input_eof;
            }
            if (inpkt->data == abort_pkt.data) {
                av_log(NULL, AV_LOG_INFO, "audio %d buffer ABORT\n", index);
                is->audio_info[index]->audio_eof = is->audio_eof_enum::eof;
                goto quit_audio;
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
                    auto dec_channel_layout = get_valid_channel_layout(inframe->channel_layout, inframe->channels);
                    if (!dec_channel_layout)
                        dec_channel_layout = av_get_default_channel_layout(inframe->channels);
                    bool reconfigure =
                    cmp_audio_fmts(is->audio_info[index]->audio_filter_src.fmt, is->audio_info[index]->audio_filter_src.channels,
                                   (enum AVSampleFormat)inframe->format, inframe->channels) ||
                    is->audio_info[index]->audio_filter_src.channel_layout != dec_channel_layout ||
                    is->audio_info[index]->audio_filter_src.freq != inframe->sample_rate;
                    
                    if (reconfigure) {
                        av_log(NULL, AV_LOG_INFO, "audio %d reconfigure\n", index);
                        is->audio_info[index]->audio_filter_src.fmt = (enum AVSampleFormat)inframe->format;
                        is->audio_info[index]->audio_filter_src.channels = inframe->channels;
                        is->audio_info[index]->audio_filter_src.channel_layout = dec_channel_layout;
                        is->audio_info[index]->audio_filter_src.freq = inframe->sample_rate;
                        
                        graph = std::shared_ptr<AVFilterGraph>(avfilter_graph_alloc(), [](AVFilterGraph *ptr) { avfilter_graph_free(&ptr); });
                        if (!is->configure_audio_filters(&filt_in, &filt_out, graph.get(), is->audio_info[index]->audio_filter_src, audio_out_sample_rate, audio_out_channels))
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
                    int out_size = sizeof(float) * out_samples * audio_out_channels;
                    int64_t pts_t;
                    int64_t delta_pts_t = AV_NOPTS_VALUE;
                    double pts = 0;
                    double delta_pts = 0;
                    if ((pts_t = audio_frame_out.best_effort_timestamp) != AV_NOPTS_VALUE) {
                        if(is->audio_info[index]->audio_start_pts != AV_NOPTS_VALUE && is->audio_info[index]->audio_start_pts > 0x1FFFFFFFF && pts_t < is->audio_info[index]->audio_start_pts) {
                            av_log(NULL, AV_LOG_INFO, "audio %d pts wrap-around %lld->%lld\n", index, is->audio_info[index]->audio_start_pts, pts_t);

                            pts_t += 0x1FFFFFFFF;
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
                        if(is->video_info[is->main_video]->video_start_pts != AV_NOPTS_VALUE && is->video_info[is->main_video]->video_start_pts > 0x1FFFFFFFF && pts_t < is->video_info[is->main_video]->video_start_pts - 0x1FFFFFFF) {
                            pts_t += 0x1FFFFFFFF;
                        }
                        av_log(NULL, AV_LOG_INFO, "audio %d pts %lld\n", index, pts_t);
                        pts = av_q2d(is->audio_info[index]->audio_st->time_base)*pts_t;
                        av_log(NULL, AV_LOG_INFO, "audio %d clock %f\n", index, pts);
                        
                        pts -= is->video_info[is->main_video]->video_clock_start;
                        av_log(NULL, AV_LOG_INFO, "audio %d sync clock %f\n", index, pts);
                        pts_t = pts / av_q2d(is->audio_info[index]->audio_st->time_base);
                        av_log(NULL, AV_LOG_INFO, "audio %d sync pts %lld\n", index, pts_t);
                        
                        if(isnan(is->audio_info[index]->audio_clock_start)) {
                            av_log(NULL, AV_LOG_INFO, "set audio %d start %f, %lld\n", index, pts, pts_t);
                            is->audio_info[index]->audio_clock_start = pts;
                            is->audio_info[index]->audio_start_pts = pts_t;
                        }
                        if(is->audio_info[index]->audio_last_pts_t != AV_NOPTS_VALUE) {
                            delta_pts_t = pts_t - is->audio_info[index]->audio_last_pts_t;
                            delta_pts = av_q2d(is->audio_info[index]->audio_st->time_base)*delta_pts_t;
                        }
                        else if (pts > 0) {
                            delta_pts_t = pts_t;
                            delta_pts = pts;
                        }
                        else {
                            av_frame_unref(&audio_frame_out);
                            av_log(NULL, AV_LOG_INFO, "audio %d pts %f, %lld < 0 skip\n", index, pts, pts_t);
                            continue;
                        }
                    }
                    av_log(NULL, AV_LOG_INFO, "audio %d pts %f, %lld\n", index, pts, pts_t);
                    
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

                    if(delta_sample + out_samples < 0) {
                        av_log(NULL, AV_LOG_INFO, "audio %d skip\n", index);
                        av_frame_unref(&audio_frame_out);
                        continue;
                    }
                    if (abs(delta_sample) < 1500) {
                        pts += (double)(out_samples) / audio_out_sample_rate;
                        is->audio_info[index]->frame_count += out_samples;
                        
                        pts_t = av_rescale_q(is->audio_info[index]->frame_count, av_make_q(1, audio_out_sample_rate), is->audio_info[index]->audio_st->time_base);
                        is->audio_info[index]->audio_last_pts_t = pts_t;
                        is->audio_info[index]->audio_last_pts = pts;

                        av_log(NULL, AV_LOG_INFO, "audio %d last pts %lld\n", index, pts_t);

                        encode(stream, (double)is->audio_info[index]->frame_count / audio_out_sample_rate, (uint8_t *)audio_buf, out_size, index);
                    }
                    else {
                        if(delta_sample < 0) {
                            av_log(NULL, AV_LOG_INFO, "audio %d 0 delta %lld < 0\n", index, delta_sample);

                            int offset = int(-delta_sample);
                            int fix_out_size = sizeof(float) * int(out_samples+delta_sample) * audio_out_channels;
                            pts += (double)(out_samples+delta_sample) / audio_out_sample_rate;
                            is->audio_info[index]->frame_count += out_samples+delta_sample;
                            
                            pts_t = av_rescale_q(is->audio_info[index]->frame_count, av_make_q(1, audio_out_sample_rate), is->audio_info[index]->audio_st->time_base);
                            is->audio_info[index]->audio_last_pts_t = pts_t;
                            is->audio_info[index]->audio_last_pts = pts;
                            av_log(NULL, AV_LOG_INFO, "audio %d last pts %lld\n", index, pts_t);

                            encode(stream, (double)is->audio_info[index]->frame_count / audio_out_sample_rate, (uint8_t *)&audio_buf[offset*audio_out_channels], fix_out_size, index);
                        }
                        else {
                            av_log(NULL, AV_LOG_INFO, "audio %d 0 delta %lld > 0\n", index, delta_sample);
                            
                            int pad_size = sizeof(float) * int(delta_sample) * audio_out_channels;
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
                            
                            pts_t = av_rescale_q(is->audio_info[index]->frame_count, av_make_q(1, audio_out_sample_rate), is->audio_info[index]->audio_st->time_base);
                            is->audio_info[index]->audio_last_pts_t = pts_t;
                            is->audio_info[index]->audio_last_pts = pts;

                            av_log(NULL, AV_LOG_INFO, "audio %d last pts %lld\n", index, pts_t);

                            encode(stream, (double)is->audio_info[index]->frame_count / audio_out_sample_rate, (uint8_t *)audio_buf, out_size, index);
                        }
                    }
                    av_frame_unref(&audio_frame_out);

                    printf("%d,%f,%f,%lld\n", index, (double)is->audio_info[index]->frame_count / audio_out_sample_rate, pts, pts_t);
                    
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
                                    memset(silence_buf, 0, sizeof(float) * out_samples * audio_out_channels);
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
    return;
}

bool Converter::configure_audio_filters(AVFilterContext **filt_in, AVFilterContext **filt_out, AVFilterGraph *graph, const AudioParams &audio_filter_src, int audio_out_sample_rate, int audio_out_channels)
{
    char asrc_args[256] = { 0 };
    AVFilterContext *filt_asrc = NULL, *filt_asink = NULL;

    if (!graph) return false;
    
    int ret = snprintf(asrc_args, sizeof(asrc_args),
                       "sample_rate=%d:sample_fmt=%s:channels=%d:time_base=%d/%d",
                       audio_filter_src.freq, av_get_sample_fmt_name(audio_filter_src.fmt),
                       audio_filter_src.channels,
                       1, audio_filter_src.freq);
    if (audio_filter_src.channel_layout)
        snprintf(asrc_args + ret, sizeof(asrc_args) - ret,
                 ":channel_layout=0x%" PRIx64, audio_filter_src.channel_layout);
    
    if (avfilter_graph_create_filter(&filt_asrc,
                                     avfilter_get_by_name("abuffer"), "ffplay_abuffer",
                                     asrc_args, NULL, graph) < 0)
        return false;
    
    if (avfilter_graph_create_filter(&filt_asink,
                                     avfilter_get_by_name("abuffersink"), "ffplay_abuffersink",
                                     NULL, NULL, graph) < 0)
        return false;

    const enum AVSampleFormat out_sample_fmts[] = {AV_SAMPLE_FMT_FLT, AV_SAMPLE_FMT_NONE};
    if (av_opt_set_int_list(filt_asink, "sample_fmts", out_sample_fmts, -1, AV_OPT_SEARCH_CHILDREN) < 0)
        return false;

    const int64_t out_channel_layouts[] = {av_get_default_channel_layout(audio_out_channels), -1};
    if (av_opt_set_int_list(filt_asink, "channel_layouts", out_channel_layouts, -1, AV_OPT_SEARCH_CHILDREN) < 0)
        return false;

    const int out_sample_rates[] = {audio_out_sample_rate, -1};
    if (av_opt_set_int_list(filt_asink, "sample_rates", out_sample_rates, -1, AV_OPT_SEARCH_CHILDREN) < 0)
        return false;

    AVFilterContext *filt_last = filt_asrc;

    if (avfilter_link(filt_last, 0, filt_asink, 0) != 0)
        return false;
    
    if (avfilter_graph_config(graph, NULL) < 0)
        return false;
    
    *filt_in = filt_asrc;
    *filt_out = filt_asink;
    return true;
}

int subtitle_thread(Converter *is, int index)
{
    av_log(NULL, AV_LOG_INFO, "subtitle_thread %d start\n", index);
    auto encode = ((struct convert_param *)is->param)->encode_text;
    auto stream = ((struct convert_param *)is->param)->stream;
    AVPacket packet = { 0 };
    std::shared_ptr<SwsContext> sub_convert_ctx;
    int64_t old_serial = 0;

    while(is->main_video < 0) {
        if(is->IsQuit())
            break;
        av_usleep(10*1000);
    }

    is->subtitle_info[index]->subpictq_active_serial = av_gettime();
    while (!is->IsQuit()) {
        AVCodecContext *subtitle_ctx = is->subtitle_info[index]->subtitle_ctx.get();
        AVRational timebase = is->pFormatCtx->streams[is->subtitleStream[index]]->time_base;
        if (is->subtitle_info[index]->subtitleq.get(&packet, 1) < 0) {
            // means we quit getting packets
            av_log(NULL, AV_LOG_INFO, "subtitle Quit %d\n", index);
            break;
        }
    retry:
        if (packet.data == flush_pkt.data) {
            av_log(NULL, AV_LOG_INFO, "subtitle buffer flush %d\n", index);
            avcodec_flush_buffers(subtitle_ctx);
            old_serial = 0;
            packet = { 0 };
            continue;
        }
        if (packet.data == eof_pkt.data) {
            av_log(NULL, AV_LOG_INFO, "subtitle buffer EOF %d\n", index);
            packet = { 0 };
            while (!is->IsQuit() && is->subtitle_info[index]->subtitleq.get(&packet, 0) == 0)
                av_usleep(100*1000);
            if (is->IsQuit()) break;
            goto retry;
        }
        if (packet.data == abort_pkt.data) {
            av_log(NULL, AV_LOG_INFO, "subtitle buffer ABORT %d\n", index);
            packet = { 0 };
            break;
        }
        int got_frame = 0;
        int ret;
        AVSubtitle sub;
        if ((ret = avcodec_decode_subtitle2(subtitle_ctx, &sub, &got_frame, &packet)) < 0) {
            av_packet_unref(&packet);
            char buf[AV_ERROR_MAX_STRING_SIZE];
            char *errstr = av_make_error_string(buf, AV_ERROR_MAX_STRING_SIZE, ret);
            av_log(NULL, AV_LOG_ERROR, "error avcodec_decode_subtitle2() %d %s\n", ret, errstr);
            return -1;
        }
        if(sub.pts == AV_NOPTS_VALUE)
            sub.pts = packet.pts;
        av_packet_unref(&packet);
        if (got_frame == 0) continue;

        double pts = 0;

        //printf("subtitle pts %lld\n", sub.pts);
        if (sub.pts != AV_NOPTS_VALUE)
            pts = sub.pts * av_q2d(timebase);
        std::shared_ptr<SubtitlePicture> sp(new SubtitlePicture);
        sp->pts = pts;
        sp->serial = av_gettime();
        while (old_serial >= sp->serial) sp->serial++;
        old_serial = sp->serial;
        sp->start_display_time = sub.start_display_time;
        sp->end_display_time = sub.end_display_time;
        sp->numrects = sub.num_rects;
        sp->subrects.reset(new std::shared_ptr<AVSubtitleRect>[sub.num_rects]());
        sp->type = sub.format;
        
        if(sp->type == 1 || (sp->type == 0 && is->main_subtitle == index)) {
            for (size_t i = 0; i < sub.num_rects; i++)
            {
                sp->subw = subtitle_ctx->width ? subtitle_ctx->width : is->video_info[is->main_video]->video_ctx->width;
                sp->subh = subtitle_ctx->height ? subtitle_ctx->height : is->video_info[is->main_video]->video_ctx->height;

                if (((sp->subrects[i] = std::shared_ptr<AVSubtitleRect>(
                    (AVSubtitleRect *)av_mallocz(sizeof(AVSubtitleRect)),
                    [](AVSubtitleRect *p) {
                    if (p->text)
                        av_free(p->text);
                    if (p->ass)
                        av_free(p->ass);
                    if (p->data[0])
                        av_free(p->data[0]);
                    av_free(p);
                })) == NULL)) {
                    av_log(NULL, AV_LOG_FATAL, "Cannot allocate subtitle data\n");
                    return -1;
                }

                sp->subrects[i]->type = sub.rects[i]->type;
                if (sub.rects[i]->ass)
                    sp->subrects[i]->ass = av_strdup(sub.rects[i]->ass);
                if (sub.rects[i]->text)
                    sp->subrects[i]->text = av_strdup(sub.rects[i]->text);
                if (sub.format == 0) {
                    int width = is->video_info[is->main_video]->video_ctx->width * is->video_info[is->main_video]->video_aspect;
                    int height = is->video_info[is->main_video]->video_ctx->height;
                    double ax = 1;
                    double ay = 1;
                    int offsetx = 0;
                    int offsety = 0;
                    if((double)width/height > 16.0/9.0) {
                        ax = 1920.0/width;
                        ay = ax;
                        offsety = (1080 - height*ay)/2;
                    }
                    else {
                        ay = 1080.0/height;
                        ax = ay;
                        offsetx = (1920 - width*ax)/2;
                    }
                    width = sub.rects[i]->w * is->video_info[is->main_video]->video_aspect * ax;
                    height = sub.rects[i]->h * ay;
                    
                    if (av_image_alloc(sp->subrects[i]->data, sp->subrects[i]->linesize, width, height, AV_PIX_FMT_ARGB, 16) < 0) {
                        av_log(NULL, AV_LOG_FATAL, "Cannot allocate subtitle data\n");
                        return -1;
                    }
                    sub_convert_ctx = std::shared_ptr<SwsContext>(sws_getCachedContext(NULL,
                        sub.rects[i]->w, sub.rects[i]->h, AV_PIX_FMT_PAL8,
                        width, height, AV_PIX_FMT_ARGB,
                        SWS_BICUBIC, NULL, NULL, NULL), &sws_freeContext);
                    if (!sub_convert_ctx) {
                        av_log(NULL, AV_LOG_FATAL, "Cannot initialize the sub conversion context\n");
                        return -1;
                    }
                    sws_scale(sub_convert_ctx.get(),
                        sub.rects[i]->data, sub.rects[i]->linesize,
                        0, sub.rects[i]->h, sp->subrects[i]->data, sp->subrects[i]->linesize);
                    sp->subrects[i]->w = width;
                    sp->subrects[i]->h = height;
                    sp->subrects[i]->x = sub.rects[i]->x * ax * is->video_info[is->main_video]->video_aspect + offsetx;
                    sp->subrects[i]->y = sub.rects[i]->y * ay + offsety;
                }
            }
            if (sp->type == 0) {
                is->subtitle_info[index]->subpictq.put(sp);
            }
            else if (sp->type == 1) {
                bool ass = false;
                std::ostringstream os;
                for (int i = 0; i < sp->numrects; i++) {
                    if (sp->subrects[i]->text) {
                        os << sp->subrects[i]->text << std::endl;
                    }
                    if (sp->subrects[i]->ass) {
                        os << sp->subrects[i]->ass << std::endl;
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
                double st = sp->pts + (double)sp->start_display_time / 1000 - vst;
                double et = sp->pts + (double)sp->end_display_time / 1000 - vst;
                encode(stream, st, et, os.str().c_str(), ass?1:0, is->subtitle_info[index]->textIndex);
            }
        }
        avsubtitle_free(&sub);
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

        if (pts > sp->pts + (double)sp->end_display_time / 1000)
            subtitle->subpictq.get(sp);

        if (pts <= sp->pts + (double)sp->end_display_time / 1000 &&
            pts >= sp->pts + (double)sp->start_display_time / 1000) {

            if (sp->type == 0) {
                for (int i = 0; i < sp->numrects; i++) {
                    int s_w = sp->subrects[i]->w;
                    int s_h = sp->subrects[i]->h;
                    int s_x = sp->subrects[i]->x;
                    int s_y = sp->subrects[i]->y;
                    for(int y = s_y, sy = 0; y < output.height && sy < s_h; y++, sy++){
                        uint8_t *sublp = sp->subrects[i]->data[0];
                        uint8_t *displp = output.data[0];
                        sublp = sublp + sy * sp->subrects[i]->linesize[0];
                        displp = displp + y * output.linesize[0];
                        for(int x = s_x, sx = 0; x < output.width && sx < s_w; x++, sx++){
                            uint8_t *subp = &sublp[sx * 4];
                            uint8_t *disp = &displp[x * 4];
                            double a = subp[0] / 255.0;
                            uint8_t r = subp[1];
                            uint8_t g = subp[2];
                            uint8_t b = subp[3];
                            disp[0] = disp[0]*(1-a) + b*a;
                            disp[1] = disp[1]*(1-a) + g*a;
                            disp[2] = disp[2]*(1-a) + r*a;
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
    AVCodec *codec;
    
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
        if(audio->audio_eof != audio_eof_enum::eof) {
            isAllQuit = false;
            break;
        }
    }
    if(isAllQuit) {
        for(const auto &video: video_info) {
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
