//
//  player_base.cpp
//  ffplayer
//
//  Created by rei6 on 2019/03/21.
//  Copyright © 2019 lithium03. All rights reserved.
//

#include "player_base.hpp"
#include "player_param.h"

AVPacket flush_pkt;
AVPacket eof_pkt;
AVPacket abort_pkt;

Uint32 messageBase;

#ifdef __cplusplus
extern "C" {
#endif /* __cplusplus */

void setParam(struct stream_param * param)
{
    Player *player = new Player();
    player->update_info = param->update_info;
    player->rotate_lock = param->isPhone;
    player->start_skip = param->start;
    player->audio_sync_delay = param->latency;
    player->name = std::string(param->name);
    player->window = param->window;
    player->renderer = param->renderer;
    player->font = param->font;
    {
        SDL_Surface *bmpSurf = SDL_LoadBMP(param->image1);
        player->image1 = std::shared_ptr<SDL_Texture>(SDL_CreateTextureFromSurface(param->renderer, bmpSurf), &SDL_DestroyTexture);
        SDL_FreeSurface(bmpSurf);
    }
    {
        SDL_Surface *bmpSurf = SDL_LoadBMP(param->image2);
        player->image2 = std::shared_ptr<SDL_Texture>(SDL_CreateTextureFromSurface(param->renderer, bmpSurf), &SDL_DestroyTexture);
        SDL_FreeSurface(bmpSurf);
    }
    {
        SDL_Surface *bmpSurf = SDL_LoadBMP(param->image3);
        player->image3 = std::shared_ptr<SDL_Texture>(SDL_CreateTextureFromSurface(param->renderer, bmpSurf), &SDL_DestroyTexture);
        SDL_FreeSurface(bmpSurf);
    }
    {
        SDL_Surface *bmpSurf = SDL_LoadBMP(param->image4);
        player->image4 = std::shared_ptr<SDL_Texture>(SDL_CreateTextureFromSurface(param->renderer, bmpSurf), &SDL_DestroyTexture);
        SDL_FreeSurface(bmpSurf);
    }
    int tmp_w, tmp_h;
    SDL_GetRendererOutputSize(param->renderer, &tmp_w, &tmp_h);
    if (tmp_w < tmp_h && player->rotate_lock) {
        player->turn = true;
    }
    else {
        player->turn = false;
    }
    messageBase = param->messageBase;
    param->player = player;
    player->param = param;
    player->schedule_refresh(40);
}

void setImage(struct stream_param *param, void *mem, int len)
{
    Player *player = (Player *)param->player;
    SDL_Surface *surface = IMG_Load_RW(SDL_RWFromMem(mem, len), 1);
    if (surface) {
        player->statictexture = std::shared_ptr<SDL_Texture>(SDL_CreateTextureFromSurface(player->renderer, surface), SDL_DestroyTexture);
        SDL_FreeSurface(surface);
    }
}
    
double getPosition(struct stream_param * param)
{
    double pos = ((Player *)param->player)->playtime;
    double len = ((Player *)param->player)->duration;
    return (pos < len - 1)? pos : 0;
}
    
void freeParam(struct stream_param * param)
{
    delete (Player *)param->player;
}

int eventLoop(struct stream_param * param)
{
    int ret = 0;
    Player *player = (Player *)param->player;

    SDL_Event event;
    
//    if (SDL_PollEvent(&event) == 0)
//        return ret;
    SDL_WaitEvent(&event);
    switch (event.type) {
        case SDL_QUIT:
        {
            player->Finalize();
            ret = 1;
        }
            break;
        case SDL_APP_WILLENTERBACKGROUND:
        {
            player->ishidden = true;
            SDL_SetWindowFullscreen(player->window, 0);
        }
            break;
        case SDL_APP_DIDENTERFOREGROUND:
        {
            player->ishidden = false;
            player->change_pause = true;
            player->schedule_refresh(100);
            SDL_SetWindowFullscreen(player->window, SDL_WINDOW_FULLSCREEN);
            SDL_RaiseWindow(player->window);
        }
            break;
        case SDL_DISPLAYEVENT:
        {
            switch (event.display.event) {
                case SDL_DISPLAYEVENT_ORIENTATION:
                    break;
                    
                default:
                    break;
            }
        }
        case SDL_FINGERDOWN:
        {
            float x = event.tfinger.x;
            float y = event.tfinger.y;
            if (player->display_on) {
                int tmp_w, tmp_h;
                SDL_GetRendererOutputSize(player->renderer, &tmp_w, &tmp_h);

                if (player->turn) {
                    if (tmp_w * x < 80) {
                        param->seeking = true;
                    }
                    else {
                        param->seeking = false;
                    }
                }
                else {
                    if (tmp_h * y > tmp_h - 80) {
                        param->seeking = true;
                    }
                    else {
                        param->seeking = false;
                    }
                }
            }
        }
            break;
        case SDL_FINGERMOTION:
        {
            if (player->IsQuit())
                break;
            float x = event.tfinger.x;
            float y = event.tfinger.y;
            int tmp_w, tmp_h;

            if (param->seeking) {
                SDL_GetRendererOutputSize(player->renderer, &tmp_w, &tmp_h);

                if (player->turn) {
                    if (tmp_w * x < 80) {
                        param->seeking = true;
                    }
                    else {
                        param->seeking = false;
                    }
                }
                else {
                    if (tmp_h * y > tmp_h - 80) {
                        param->seeking = true;
                    }
                    else {
                        param->seeking = false;
                    }
                }
            }
            if (param->seeking) {
                float frac = (player->turn) ? y : x;
                player->EventOnSeek(frac, true, false);
            }
        }
            break;
        case SDL_FINGERUP:
        {
            if (player->IsQuit())
                break;
            float x = event.tfinger.x;
            float y = event.tfinger.y;
            if (player->display_on) {
                int tmp_w, tmp_h;
                SDL_GetRendererOutputSize(player->renderer, &tmp_w, &tmp_h);
                if (player->turn) {
                    if ((tmp_w * x > tmp_w - 150) && (tmp_h * y < 150)) {
                        player->Quit();
                        break;
                    }
                    if ((tmp_h * y > tmp_h/2 - 50) && (tmp_h * y < tmp_h/2 + 50) &&
                        (tmp_w * x > 150) && (tmp_w * x < 250)) {
                        player->TogglePause();
                        break;
                    }
                    if ((tmp_h * y > tmp_h/2 - 200) && (tmp_h * y < tmp_h/2 - 100) &&
                        (tmp_w * x > 150) && (tmp_w * x < 250)) {
                        player->EventOnSeek(-30, false, true);
                        break;
                    }
                    if ((tmp_h * y > tmp_h/2 + 100) && (tmp_h * y < tmp_h/2 + 200) &&
                        (tmp_w * x > 150) && (tmp_w * x < 250)) {
                        player->EventOnSeek(30, false, true);
                        break;
                    }
                    if ((tmp_w * x > tmp_w * 2 / 6) && (tmp_w * x < tmp_w * 2 / 6 + 100) &&
                        (tmp_h * y > 100) && (tmp_h * y < 200)) {
                        player->stream_cycle_channel(AVMEDIA_TYPE_AUDIO);
                        break;
                    }
                    if ((tmp_w * x > tmp_w * 3 / 6) && (tmp_w * x < tmp_w * 3 / 6 + 100) &&
                        (tmp_h * y > 100) && (tmp_h * y < 200)) {
                        player->stream_cycle_channel(AVMEDIA_TYPE_VIDEO);
                        break;
                    }
                    if ((tmp_w * x > tmp_w * 4 / 6) && (tmp_w * x < tmp_w * 4 / 6 + 100) &&
                        (tmp_h * y > 100) && (tmp_h * y < 200)) {
                        player->stream_cycle_channel(AVMEDIA_TYPE_SUBTITLE);
                        break;
                    }
                    if (param->seeking && (tmp_w * x < 80)) {
                        player->EventOnSeek(y, true, true);
                        param->seeking = false;
                        break;
                    }
                }
                else {
                    if ((tmp_w * x < 150) && (tmp_h * y < 150)) {
                        player->Quit();
                        break;
                    }
                    if ((tmp_w * x > tmp_w/2 - 50) && (tmp_w * x < tmp_w/2 + 50) &&
                        (tmp_h * y < tmp_h - 150) && (tmp_h * y > tmp_h - 250)) {
                        player->TogglePause();
                        break;
                    }
                    if ((tmp_w * x > tmp_w/2 - 200) && (tmp_w * x < tmp_w/2 - 100) &&
                        (tmp_h * y < tmp_h - 150) && (tmp_h * y > tmp_h - 250)) {
                        player->EventOnSeek(-30, false, true);
                        break;
                    }
                    if ((tmp_w * x > tmp_w/2 + 100) && (tmp_w * x < tmp_w/2 + 200) &&
                        (tmp_h * y < tmp_h - 150) && (tmp_h * y > tmp_h - 250)) {
                        player->EventOnSeek(30, false, true);
                        break;
                    }
                    if ((tmp_w * x > 100) && (tmp_w * x < 200) &&
                        (tmp_h * y > tmp_h * 2 / 6) && (tmp_h * y < tmp_h * 2 / 6 + 100)) {
                        player->stream_cycle_channel(AVMEDIA_TYPE_SUBTITLE);
                        break;
                    }
                    if ((tmp_w * x > 100) && (tmp_w * x < 200) &&
                        (tmp_h * y > tmp_h * 3 / 6) && (tmp_h * y < tmp_h * 3 / 6 + 100)) {
                        player->stream_cycle_channel(AVMEDIA_TYPE_VIDEO);
                        break;
                    }
                    if ((tmp_w * x > 100) && (tmp_w * x < 200) &&
                        (tmp_h * y > tmp_h * 4 / 6) && (tmp_h * y < tmp_h * 4 / 6 + 100)) {
                        player->stream_cycle_channel(AVMEDIA_TYPE_AUDIO);
                        break;
                    }
                    if (param->seeking && (tmp_h * y > tmp_h - 80)) {
                        player->EventOnSeek(x, true, true);
                        param->seeking = false;
                        break;
                    }
                }
            }
            player->display_on = !player->display_on;
        }
            break;
        default:
            if (event.type == param->messageBase) {
                //QUIT_EVENT
                player->Finalize();
                ret = 1;
            }
            else if (event.type == param->messageBase + 1) {
                //FF_PAUSE_EVENT
                player->TogglePause();
            }
            else if (event.type == param->messageBase + 2) {
                //FF_REFRESH_EVENT
                player->video_refresh_timer();
            }
            break;
    }
    
    return ret;
}

int externalPause(struct stream_param * param, int pause)
{
    Player *player = (Player *)param->player;
    if(!player)
        return 1;
    
    if (pause) {
        if(!player->pause) {
            SDL_Event event;
            memset(&event, 0, sizeof(event));
            //FF_PAUSE_EVENT
            event.type = param->messageBase + 1;
            SDL_PushEvent(&event);
        }
    }
    else {
        if(player->pause) {
            SDL_Event event;
            memset(&event, 0, sizeof(event));
            //FF_PAUSE_EVENT
            event.type = param->messageBase + 1;
            SDL_PushEvent(&event);
        }
    }
    return 0;
}

int externalLatency(struct stream_param * param, double latency)
{
    Player *player = (Player *)param->player;
    if(!player)
        return 1;
    
    bool playing = !player->pause;
    if (playing) {
        SDL_Event event;
        memset(&event, 0, sizeof(event));
        //FF_PAUSE_EVENT
        event.type = param->messageBase + 1;
        SDL_PushEvent(&event);
    }
    player->audio_sync_delay = latency;

    if (playing) {
        SDL_Event event;
        memset(&event, 0, sizeof(event));
        //FF_PAUSE_EVENT
        event.type = param->messageBase + 1;
        SDL_PushEvent(&event);
    }
    return 0;
}

int externalSeek(struct stream_param * param, double position)
{
    Player *player = (Player *)param->player;
    if(!player)
        return 1;

    if (player->pts_rollover) {
        double ratio = position;
        if (!isnan(player->video_clock_start))
            ratio -= player->video_clock_start;
        else if (!isnan(player->audio_clock_start))
            ratio -= player->audio_clock_start;
        ratio /= player->get_duration();
        av_log(NULL, AV_LOG_INFO, "ratio %.2f\n", ratio);
        player->stream_seek(ratio);
    }
    else {
        int64_t ts = (int64_t)(position * AV_TIME_BASE);
        if (player->start_time_org != AV_NOPTS_VALUE){
            ts += player->start_time_org;
        }
        player->stream_seek(ts, 0);
    }
    return 0;
}

    
#ifdef __cplusplus
}
#endif /* __cplusplus */

PacketQueue::PacketQueue(Player *parent) : first_pkt(NULL), last_pkt(NULL), mutex(SDL_CreateMutex(), SDL_DestroyMutex),
cond(SDL_CreateCond(), SDL_DestroyCond)
{
    this->parent = parent;
}

PacketQueue::~PacketQueue()
{
    clear();
}

void PacketQueue::AbortQueue()
{
    AVPacketList *pktabort;
    pktabort = (AVPacketList *)av_mallocz(sizeof(AVPacketList));
    if (!pktabort)
        return;
    pktabort->pkt = abort_pkt;
    pktabort->next = NULL;
    
    
    SDL_LockMutex(mutex.get());
    
    AVPacketList *pkt1;
    for (auto pkt = first_pkt; pkt != NULL; pkt = pkt1) {
        pkt1 = pkt->next;
        if ((pkt->pkt.data != flush_pkt.data) &&
            (pkt->pkt.data != eof_pkt.data) &&
            (pkt->pkt.data != abort_pkt.data)) {
            
            av_packet_unref(&pkt->pkt);
        }
        av_free(pkt);
    }
    last_pkt = NULL;
    first_pkt = NULL;
    nb_packets = 0;
    size = 0;
    
    first_pkt = pktabort;
    last_pkt = pktabort;
    nb_packets++;
    size += pktabort->pkt.size;
    SDL_CondSignal(cond.get());
    
    SDL_UnlockMutex(mutex.get());
    return;
}

int PacketQueue::putEOF()
{
    AVPacketList *pkt1;
    
    pkt1 = (AVPacketList *)av_mallocz(sizeof(AVPacketList));
    if (!pkt1)
        return -1;
    pkt1->pkt = eof_pkt;
    pkt1->next = NULL;
    
    
    SDL_LockMutex(mutex.get());
    
    if (!last_pkt)
        first_pkt = pkt1;
    else
        last_pkt->next = pkt1;
    last_pkt = pkt1;
    nb_packets++;
    size += pkt1->pkt.size;
    SDL_CondSignal(cond.get());
    
    SDL_UnlockMutex(mutex.get());
    return 0;
}

int PacketQueue::put(AVPacket *pkt)
{
    AVPacketList *pkt1;
    
    pkt1 = (AVPacketList *)av_mallocz(sizeof(AVPacketList));
    if (!pkt1)
        return -1;
    pkt1->pkt = *pkt;
    pkt1->next = NULL;
    
    
    SDL_LockMutex(mutex.get());
    
    if (!last_pkt)
        first_pkt = pkt1;
    else
        last_pkt->next = pkt1;
    last_pkt = pkt1;
    nb_packets++;
    size += pkt1->pkt.size;
    SDL_CondSignal(cond.get());
    
    SDL_UnlockMutex(mutex.get());
    return 0;
}

int PacketQueue::get(AVPacket *pkt, int block)
{
    AVPacketList *pkt1;
    int ret;
    
    SDL_LockMutex(mutex.get());
    
    for (;;) {
        
        if (parent->IsQuit()) {
            ret = -1;
            break;
        }
        
        pkt1 = first_pkt;
        if (pkt1) {
            first_pkt = pkt1->next;
            if (!first_pkt)
                last_pkt = NULL;
            nb_packets--;
            size -= pkt1->pkt.size;
            *pkt = pkt1->pkt;
            av_free(pkt1);
            ret = 1;
            break;
        }
        else if (!block) {
            ret = 0;
            break;
        }
        else {
            SDL_CondWait(cond.get(), mutex.get());
        }
    }
    SDL_UnlockMutex(mutex.get());
    return ret;
}

void PacketQueue::flush()
{
    AVPacketList *pktflush;
    
    pktflush = (AVPacketList *)av_mallocz(sizeof(AVPacketList));
    if (!pktflush)
        return;
    pktflush->pkt = flush_pkt;
    pktflush->next = NULL;
    
    SDL_LockMutex(mutex.get());
    AVPacketList *pkt1;
    for (auto pkt = first_pkt; pkt != NULL; pkt = pkt1) {
        pkt1 = pkt->next;
        if ((pkt->pkt.data != flush_pkt.data) &&
            (pkt->pkt.data != eof_pkt.data) &&
            (pkt->pkt.data != abort_pkt.data)) {
            
            av_packet_unref(&pkt->pkt);
        }
        av_free(pkt);
    }
    last_pkt = NULL;
    first_pkt = NULL;
    nb_packets = 0;
    size = 0;
    
    first_pkt = pktflush;
    last_pkt = pktflush;
    nb_packets++;
    size += pktflush->pkt.size;
    SDL_CondSignal(cond.get());
    
    SDL_UnlockMutex(mutex.get());
    return;
}

void PacketQueue::clear()
{
    AVPacketList *pkt1;
    
    SDL_LockMutex(mutex.get());
    for (auto pkt = first_pkt; pkt != NULL; pkt = pkt1) {
        pkt1 = pkt->next;
        if ((pkt->pkt.data != flush_pkt.data) &&
            (pkt->pkt.data != eof_pkt.data) &&
            (pkt->pkt.data != abort_pkt.data)) {
            
            av_packet_unref(&pkt->pkt);
        }
        av_free(pkt);
    }
    last_pkt = NULL;
    first_pkt = NULL;
    nb_packets = 0;
    size = 0;
    SDL_UnlockMutex(mutex.get());
}

/////////////////////////////////////////////////////////////////////////////////////

VideoPicture::~VideoPicture()
{
    this->Free();
}

bool VideoPicture::Allocate(int width, int height)
{
    Free();
    if (av_image_alloc(bmp.data, bmp.linesize, width, height, AV_PIX_FMT_YUV420P, 8) < 0) return false;
    this->width = width;
    this->height = height;
    this->allocated = true;
    return true;
}

void VideoPicture::Free()
{
    if (allocated) {
        this->allocated = false;
        av_freep(&bmp.data[0]);
        av_freep(&bmp);
        height = width = 0;
    }
}

////////////////////////////////////////////////////////////////////////////////////////

SubtitlePictureQueue::SubtitlePictureQueue(Player *parent) : mutex(SDL_CreateMutex(), SDL_DestroyMutex),
cond(SDL_CreateCond(), SDL_DestroyCond)
{
    this->parent = parent;
}

SubtitlePictureQueue::~SubtitlePictureQueue()
{
    clear();
}

void SubtitlePictureQueue::clear()
{
    SDL_LockMutex(mutex.get());
    while (!queue.empty())
        queue.pop();
    SDL_UnlockMutex(mutex.get());
}

void SubtitlePictureQueue::put(std::shared_ptr<SubtitlePicture> Pic)
{
    SDL_LockMutex(mutex.get());
    queue.push(Pic);
    SDL_CondSignal(cond.get());
    SDL_UnlockMutex(mutex.get());
}

int SubtitlePictureQueue::get(double pts, std::shared_ptr<SubtitlePicture> &Pic)
{
    int ret;
    SDL_LockMutex(mutex.get());
    while (true) {
        
        if (parent->IsQuit()) {
            ret = -1;
            break;
        }
        if (!queue.empty()) {
            Pic = queue.front();
            
            if (pts > Pic->pts + (double)Pic->end_display_time / 1000) {
                queue.pop();
                continue;
            }
            
            if (pts <= Pic->pts + (double)Pic->end_display_time / 1000 &&
                pts >= Pic->pts + (double)Pic->start_display_time / 1000) {
                ret = 0;
            }
            else {
                ret = 1;
            }
            break;
        }
        else {
            ret = 2;
            break;
        }
        //SDL_CondWait(cond.get(), mutex.get());
    }
    SDL_UnlockMutex(mutex.get());
    return ret;
}


/////////////////////////////////////////////////////////////////////////////////

Player::Player() : quit(false), audioq(this), subtitleq(this), subpictq(this), videoq(this),
pictq_mutex(SDL_CreateMutex(), SDL_DestroyMutex), pictq_cond(SDL_CreateCond(), SDL_DestroyCond),
screen_mutex(SDL_CreateMutex(), &SDL_DestroyMutex),
pictq_prev(&pictq[0]), remove_refresh(0)
{
    display_on = true;
}

int decode_thread(void *arg)
{
    av_log(NULL, AV_LOG_INFO, "decode_thread start\n");

    int ret = -1;
    struct stream_param *stream = (struct stream_param *)(arg);
    Player *player = (Player *)stream->player;

    int video_index = -1;
    int audio_index = -1;
    int subtitle_index = -1;
    
    player->videoStream = -1;
    player->audioStream = -1;
    player->subtitleStream = -1;

    player->start_time_org = AV_NOPTS_VALUE;
    
    player->pFormatCtx = avformat_alloc_context();
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
    player->pFormatCtx->pb = pIoCtx;
    char *filename = stream->name;
    
    av_log(NULL, AV_LOG_VERBOSE, "avformat_open_input()\n");
    // Open video file
    if (player->IsQuit() || avformat_open_input(&player->pFormatCtx, filename, NULL, NULL) != 0) {
        printf("avformat_open_input() failed %s\n", filename);
        goto failed_open;
    }
    
    av_log(NULL, AV_LOG_VERBOSE, "avformat_find_stream_info()\n");
    //pFormatCtx->max_analyze_duration = 500000;
    // Retrieve stream information
    if (player->IsQuit() || avformat_find_stream_info(player->pFormatCtx, NULL) < 0) {
        printf("avformat_find_stream_info() failed %s\n", filename);
        goto failed_run;
    }
    
    if(player->IsQuit()) {
        goto failed_run;
    }
    
    av_log(NULL, AV_LOG_VERBOSE, "av_dump_format()\n");
    // Dump information about file onto standard error
    av_dump_format(player->pFormatCtx, 0, filename, 0);
    
    if(player->IsQuit()) {
        goto failed_run;
    }
    
    for(unsigned int stream_index = 0; stream_index<player->pFormatCtx->nb_streams; stream_index++)
        player->pFormatCtx->streams[stream_index]->discard = AVDISCARD_ALL;

    if(player->IsQuit()) {
        goto failed_run;
    }
    
    av_log(NULL, AV_LOG_VERBOSE, "av_find_best_stream()\n");
    // Find the first video and audio stream
    video_index = av_find_best_stream(player->pFormatCtx, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    audio_index = av_find_best_stream(player->pFormatCtx, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    subtitle_index = av_find_best_stream(player->pFormatCtx, AVMEDIA_TYPE_SUBTITLE, -1, (audio_index >= 0 ? audio_index : video_index), NULL, 0);
    if (audio_index >= 0) {
        av_log(NULL, AV_LOG_VERBOSE, "audio stream open()\n");
        player->stream_component_open(audio_index);
    }
    if (video_index >= 0) {
        av_log(NULL, AV_LOG_VERBOSE, "video stream open()\n");
        player->stream_component_open(video_index);
    }
    if (subtitle_index >= 0) {
        av_log(NULL, AV_LOG_VERBOSE, "subtitle stream open()\n");
        player->stream_component_open(subtitle_index);
    }
    player->audio_only = false;
    player->video_only = false;
    player->sync_video = false;

    if(player->IsQuit()) {
        goto failed_run;
    }
    
    if (player->videoStream < 0 || player->audioStream < 0) {
        if (player->videoStream < 0) {
            av_log(NULL, AV_LOG_VERBOSE, "video missing\n");
            player->video_eof = true;
            player->audio_only = true;
            player->display_on = true;
            player->sync_video = false;
        }
        else {
            av_log(NULL, AV_LOG_VERBOSE, "audio missing\n");
            player->sync_video = true;
            player->audio_eof = Player::audio_eof_enum::eof;
            player->video_only = true;
        }
    }

    // main decode loop
    av_log(NULL, AV_LOG_INFO, "decode_thread read loop\n");
    for (;;) {
        if (player->IsQuit()) {
            goto finish;
        }
        // seek stuff goes here
        if (player->seek_req) {
            if(isnan(player->seek_ratio)) {
                AVRational timebase = { 1, AV_TIME_BASE };
                av_log(NULL, AV_LOG_INFO, "stream seek request receive %.2f(%lld)\n", (double)(player->seek_pos) * av_q2d(timebase), player->seek_pos);
                int stream_index = -1;
                int64_t seek_target = player->seek_pos;
                int64_t seek_min = player->seek_rel > 0 ? seek_target - player->seek_rel + 2 : INT64_MIN;
                int64_t seek_max = player->seek_rel < 0 ? seek_target - player->seek_rel - 2 : INT64_MAX;
                
                if (player->videoStream >= 0 && player->sync_video) stream_index = player->videoStream;
                else if (player->audioStream >= 0 && !player->sync_video) stream_index = player->audioStream;
                
                if (stream_index >= 0) {
                    AVRational fixtimebase = player->pFormatCtx->streams[stream_index]->time_base;
                    seek_target = av_rescale_q(seek_target, timebase, fixtimebase);
                    seek_min = player->seek_rel > 0 ? seek_target - player->seek_rel + 2 : INT64_MIN;
                    seek_max = player->seek_rel < 0 ? seek_target - player->seek_rel - 2 : INT64_MAX;
                    timebase = fixtimebase;
                }
                av_log(NULL, AV_LOG_INFO, "stream seek min = %.2f target = %.2f max = %.2f\n",
                       seek_min*av_q2d(timebase),
                       seek_target*av_q2d(timebase),
                       seek_max*av_q2d(timebase));
                int ret1 = avformat_seek_file(player->pFormatCtx, stream_index,
                                              seek_min, seek_target, seek_max,
                                              player->seek_flags);
                if (ret1 < 0) {
                    char buf[AV_ERROR_MAX_STRING_SIZE];
                    char *errstr = av_make_error_string(buf, AV_ERROR_MAX_STRING_SIZE, ret1);
                    av_log(NULL, AV_LOG_ERROR, "error avformat_seek_file() %d %s\n", ret1, errstr);
                    error = true;
                }
                if (ret1 >=0) {
                    player->pictq_active_serial = player->subpictq_active_serial = av_gettime();
                    if (player->audioStream >= 0) {
                        player->audio_eof = Player::audio_eof_enum::playing;
                        av_log(NULL, AV_LOG_INFO, "audio flush request\n");
                        player->audioq.flush();
                    }
                    if (player->videoStream >= 0) {
                        player->video_eof = false;
                        av_log(NULL, AV_LOG_INFO, "video flush request\n");
                        player->videoq.flush();
                    }
                    if (player->subtitleStream >= 0) {
                        av_log(NULL, AV_LOG_INFO, "subtitle flush request\n");
                        player->subtitleq.flush();
                    }
                }
            }
            else {
                av_log(NULL, AV_LOG_INFO, "stream seek request receive %.2f\n", player->seek_ratio);
                int stream_index = -1;
                int64_t seek_target = player->seek_ratio * player->get_duration() * player->pFormatCtx->bit_rate / 8;
                int64_t seek_min = seek_target - 1*1024*1024;
                int64_t seek_max = seek_target + 1*1024*1024;

                av_log(NULL, AV_LOG_INFO, "stream seek min = %lld target = %lld max = %lld\n",
                       seek_min,
                       seek_target,
                       seek_max);

                int ret1 = avformat_seek_file(player->pFormatCtx, stream_index,
                                              seek_min, seek_target, seek_max,
                                              AVSEEK_FLAG_BYTE);
                if (ret1 < 0) {
                    char buf[AV_ERROR_MAX_STRING_SIZE];
                    char *errstr = av_make_error_string(buf, AV_ERROR_MAX_STRING_SIZE, ret1);
                    av_log(NULL, AV_LOG_ERROR, "error avformat_seek_file() %d %s\n", ret1, errstr);
                    error = true;
                }
                if (ret1 >=0) {
                    player->pictq_active_serial = player->subpictq_active_serial = av_gettime();
                    if (player->audioStream >= 0) {
                        player->audio_eof = Player::audio_eof_enum::playing;
                        av_log(NULL, AV_LOG_INFO, "audio flush request\n");
                        player->audioq.flush();
                    }
                    if (player->videoStream >= 0) {
                        player->video_eof = false;
                        av_log(NULL, AV_LOG_INFO, "video flush request\n");
                        player->videoq.flush();
                    }
                    if (player->subtitleStream >= 0) {
                        av_log(NULL, AV_LOG_INFO, "subtitle flush request\n");
                        player->subtitleq.flush();
                    }
                }
            }
            if (player->seek_req_backorder) {
                player->seek_pos = player->seek_pos_backorder;
                player->seek_ratio = player->seek_ratio_backorder;
                player->seek_rel = player->seek_rel_backorder;
                player->seek_flags = player->seek_flags_backorder;
                player->seek_req_backorder = false;
                player->seek_ratio_backorder = NAN;
            }
            else {
                player->seek_req = false;
                player->seek_ratio = NAN;
            }
            if(player->overlay_remove_time == 0)
                player->overlay_remove_time = av_gettime();
        }
        
        if ((player->audioStream < 0 && player->videoq.size > MAX_VIDEOQ_SIZE) ||
            (player->videoStream < 0 && player->audioq.size > MAX_AUDIOQ_SIZE) ||
            (player->audioq.size > MAX_AUDIOQ_SIZE && player->videoq.size > MAX_VIDEOQ_SIZE)) {
            SDL_Delay(10);
            continue;
        }
        int ret1 = av_read_frame(player->pFormatCtx, &packet);
        if (ret1 < 0) {
            av_packet_unref(&packet);
            if (ret1 == AVERROR(EAGAIN))
                continue;
            if ((ret1 == AVERROR_EOF) || (ret1 = AVERROR(EIO))) {
                if (error || player->pFormatCtx->pb->eof_reached) {
                    if (ret1 == AVERROR_EOF) {
                        av_log(NULL, AV_LOG_INFO, "decoder EOF\n");
                    }
                    else {
                        av_log(NULL, AV_LOG_INFO, "decoder I/O Error\n");
                    }
                    if (player->videoStream >= 0) {
                        av_log(NULL, AV_LOG_INFO, "video EOF request\n");
                        player->videoq.putEOF();
                    }
                    if (player->audioStream >= 0) {
                        av_log(NULL, AV_LOG_INFO, "audio EOF request\n");
                        player->audioq.putEOF();
                    }
                    if (player->subtitleStream >= 0) {
                        av_log(NULL, AV_LOG_INFO, "subtitle EOF request\n");
                        player->subtitleq.putEOF();
                    }
                    
                    while (!(player->IsQuit() || player->seek_req)) {
                        SDL_Delay(100);
                    }
                    
                    if (player->seek_req) continue;
                    break;
                }
                error = true;
            }
            char buf[AV_ERROR_MAX_STRING_SIZE];
            char *errstr = av_make_error_string(buf, AV_ERROR_MAX_STRING_SIZE, ret1);
            av_log(NULL, AV_LOG_ERROR, "error av_read_frame() %d %s\n", ret1, errstr);
            continue;
        }
        error = false;
        if (player->start_time_org == AV_NOPTS_VALUE && player->pFormatCtx->start_time != AV_NOPTS_VALUE) {
            player->start_time_org = player->pFormatCtx->start_time;
        }
        // Is this a packet from the video stream?
        if (packet.stream_index == player->videoStream) {
            player->video_eof = false;
            player->videoq.put(&packet);
        }
        else if (packet.stream_index == player->audioStream) {
            player->audio_eof = Player::audio_eof_enum::playing;
            player->audioq.put(&packet);
            if(!player->pause)
                SDL_PauseAudioDevice(player->audio_deviceID, 0);
            player->audio_pause = false;
        }
        else if (packet.stream_index == player->subtitleStream) {
            player->subtitleq.put(&packet);
        }
        else {
            av_packet_unref(&packet);
        }
        
        if (!isnan(player->start_skip)) {
            player->start_skip -= 1;
            printf("start skip %f sec\n", player->start_skip);
            player->seek_pos = (int64_t)(player->start_skip * AV_TIME_BASE);
            if (player->pFormatCtx->start_time != AV_NOPTS_VALUE) {
                player->seek_pos += player->pFormatCtx->start_time;
            
                if (player->pFormatCtx->start_time / AV_TIME_BASE + player->get_duration() > (((int64_t)1 << 33) - 1) / 90000.0 - 3000)
                    player->seek_ratio = player->start_skip / player->get_duration();
            }
            
            player->seek_rel = 0;
            player->seek_flags = 0;
            player->seek_req = true;
            player->start_skip = NAN;
        }
    }
    /* all done - wait for it */
    while (!player->IsQuit()) {
        SDL_Delay(100);
    }
    
finish:
    ret = 0;
failed_run:
    avformat_close_input(&player->pFormatCtx);
failed_open:
    av_freep(&pIoCtx);
    if(!player->IsQuit()){
        SDL_Event event;
        memset(&event, 0, sizeof(event));
        event.type = SDL_QUIT;
        event.user.data1 = player;
        SDL_PushEvent(&event);
    }
    return ret;
}

void audio_callback(void *userdata, Uint8 *stream, int len)
{
    Player *is = (Player *)userdata;
    is->audio_callback_count++;
    int len1, audio_size;
    double pts;
    
    while (len > 0) {
        if (is->audio_buf_index >= is->audio_buf_size) {
            /* We have already sent all our data; get more */
            audio_size = is->audio_decode_frame(is->audio_buf, sizeof(is->audio_buf), &pts);
            if (audio_size < 0) {
                /* If error, output silence */
                is->audio_buf_size = MAX_AUDIO_FRAME_SIZE;
                memset(is->audio_buf, 0, is->audio_buf_size);
            }
            else {
                audio_size = is->synchronize_audio((int16_t *)is->audio_buf,
                                                   audio_size, pts);
                is->audio_buf_size = audio_size;
            }
            is->audio_buf_index = 0;
        }
        len1 = is->audio_buf_size - is->audio_buf_index;
        if (len1 > len)
            len1 = len;
        memset(stream, 0, len1);
        int volume = (is->audio_mute)? 0: (int)(is->audio_volume / 100 * SDL_MIX_MAXVOLUME);
        SDL_MixAudioFormat(stream, is->audio_buf + is->audio_buf_index, AUDIO_S16SYS, len1, volume);
        len -= len1;
        stream += len1;
        is->audio_buf_index += len1;
    }
    
    is->audio_callback_time = (double)av_gettime() / 1000000.0;
    is->audio_callback_count--;
}

int video_thread(void *arg)
{
    av_log(NULL, AV_LOG_INFO, "video_thread start\n");
    Player *is = (Player *)arg;
    AVPacket packet = { 0 }, *inpkt = &packet;
    AVCodecContext *video_ctx = is->video_ctx.get();
    AVFrame frame = { 0 }, *inframe = &frame;
    std::shared_ptr<AVFilterGraph> graph(avfilter_graph_alloc(), [](AVFilterGraph *ptr) { avfilter_graph_free(&ptr); });
    AVFilterContext *filt_out = NULL, *filt_in = NULL;
    int last_w = 0;
    int last_h = 0;
    AVPixelFormat last_format = (AVPixelFormat)-2;
    int64_t last_serial = 0, serial = 0;
    is->pictq_active_serial = 0;
    AVRational frame_rate = av_guess_frame_rate(is->pFormatCtx, is->video_st, NULL);
    
    switch (is->video_ctx->codec_id)
    {
        case AV_CODEC_ID_MJPEG:
        case AV_CODEC_ID_MJPEGB:
        case AV_CODEC_ID_LJPEG:
            is->deinterlace = false;
            break;
        default:
            is->deinterlace = true;
            break;
    }
    
    av_log(NULL, AV_LOG_INFO, "video_thread read loop\n");
    std::deque<double> lastpts;
    double pts = 0;
    double prevpts = NAN;
    while (true) {
        video_ctx = is->video_ctx.get();
        if (is->video_eof) {
            while (!is->IsQuit() && is->videoq.get(&packet, 0) == 0)
                SDL_Delay(100);
        }
        else if (is->videoq.get(&packet, 1) < 0) {
            // means we quit getting packets
            av_log(NULL, AV_LOG_INFO, "video Quit\n");
            is->video_eof = true;
            packet = { 0 };
            break;
        }
        if (is->IsQuit()) break;
        
        if (packet.data == flush_pkt.data) {
            av_log(NULL, AV_LOG_INFO, "video buffer flush\n");
            avcodec_flush_buffers(video_ctx);
            packet = { 0 };
            inpkt = &packet;
            inframe = &frame;
            is->video_eof = false;
            serial = av_gettime();
            is->pictq_active_serial = serial;
            is->frame_last_pts = NAN;
            continue;
        }
        if (packet.data == eof_pkt.data) {
            av_log(NULL, AV_LOG_INFO, "video buffer EOF\n");
            packet = { 0 };
            inpkt = NULL;
        }
        if (packet.data == abort_pkt.data) {
            av_log(NULL, AV_LOG_INFO, "video buffer ABORT\n");
            is->video_eof = true;
            packet = { 0 };
            break;
        }
        // send packet to codec context
        if (avcodec_send_packet(video_ctx, inpkt) >= 0) {
            
            // Decode video frame
            int ret;
            while ((ret = avcodec_receive_frame(video_ctx, &frame)) >= 0 || ret == AVERROR_EOF) {
                if (ret == AVERROR_EOF){
                    av_log(NULL, AV_LOG_INFO, "video EOF\n");
                    inframe = NULL;
                }
                
                if (inframe) {
                    if (frame.width != last_w ||
                        frame.height != last_h ||
                        frame.format != last_format ||
                        last_serial != serial) {
                        graph = std::shared_ptr<AVFilterGraph>(avfilter_graph_alloc(), [](AVFilterGraph *ptr) { avfilter_graph_free(&ptr); });
                        if (!is->Configure_VideoFilter(&filt_in, &filt_out, &frame, graph.get())) {
                            is->Quit();
                            return 1;
                        }
                        last_w = frame.width;
                        last_h = frame.height;
                        last_format = (AVPixelFormat)frame.format;
                        last_serial = serial;
                    }
                }
                
                
                if (inframe && av_buffersrc_write_frame(filt_in, inframe) < 0)
                    return 1;
                
                if (inframe) av_frame_unref(inframe);
                if (!filt_out) break;
                while (av_buffersink_get_frame(filt_out, &frame) >= 0) {
                    
                    if (frame.width != is->video_srcwidth || frame.height != is->video_srcheight
                        || frame.sample_aspect_ratio.den != is->video_SAR.den || frame.sample_aspect_ratio.num != is->video_SAR.num)
                    {
                        is->sws_ctx = NULL;
                        is->video_SAR = frame.sample_aspect_ratio;
                        double aspect_ratio = 0;
                        if (video_ctx->sample_aspect_ratio.num == 0) {
                            aspect_ratio = 0;
                        }
                        else {
                            aspect_ratio = av_q2d(video_ctx->sample_aspect_ratio) *
                            frame.width / frame.height;
                        }
                        if (aspect_ratio <= 0.0) {
                            aspect_ratio = (double)frame.width /
                            (double)frame.height;
                        }
                        is->video_height = video_ctx->height;
                        is->video_width = ((int)rint(is->video_height * aspect_ratio)) & ~1;
                        
                        SDL_LockMutex(is->screen_mutex.get());
                        is->subtitle.reset(NULL);
                        is->texture = std::shared_ptr<SDL_Texture>(
                                                               SDL_CreateTexture(
                                                                                 is->renderer,
                                                                                 SDL_PIXELFORMAT_YV12,
                                                                                 SDL_TEXTUREACCESS_STREAMING,
                                                                                 is->video_width,
                                                                                 is->video_height),
                                                               &SDL_DestroyTexture);
                        is->subtitlelen = 0;
                        is->subserial = 0;
                        SDL_UnlockMutex(is->screen_mutex.get());
                        
                        // initialize SWS context for software scaling
                        is->video_srcheight = frame.height;
                        is->video_srcwidth = frame.width;
                        is->sws_ctx = std::shared_ptr<SwsContext>(
                                                                  sws_getCachedContext(NULL,
                                                                                       is->video_srcwidth, is->video_srcheight,
                                                                                       video_ctx->pix_fmt, is->video_width,
                                                                                       is->video_height, AV_PIX_FMT_YUV420P,
                                                                                       SWS_BICUBLIN, NULL, NULL, NULL
                                                                                       ), &sws_freeContext);
                    } //if src.size != frame.size
                    
                    int64_t pts_t;
                    if ((pts_t = frame.best_effort_timestamp) != AV_NOPTS_VALUE) {
                        pts = pts_t * av_q2d(is->video_st->time_base);
                        //av_log(NULL, AV_LOG_INFO, "video clock %f\n", pts);
                        
                        if (isnan(is->video_clock_start)) {
                            is->video_clock_start = pts;
                        }
                    }
                    
                    if (pts > 0) {
                        lastpts.push_back(pts);
                    }
                    
                    if (fabs(prevpts - pts) < 1.0e-6 || pts == 0) {
                        if (lastpts.size() > 1) {
                            double p = lastpts.front();
                            double dpts = 0;
                            for (auto i : lastpts) {
                                dpts += i - p;
                                p = i;
                            }
                            dpts /= (lastpts.size() - 1);
                            
                            pts += dpts;
                        }
                    }
                    if (pts > 0)
                        prevpts = pts;
                    if (lastpts.size() > 30)
                        lastpts.pop_front();
                    
                    frame_rate = filt_out->inputs[0]->frame_rate;
                    pts = is->synchronize_video(&frame, pts, av_q2d(frame_rate));
                    if (is->queue_picture(&frame, pts) < 0) {
                        return 1;
                    }
                    av_frame_unref(&frame);
                } //while(av_buffersink_get_frame)
                
                if (!inframe) {
                    break;
                }
            } //while(avcodec_receive_frame)
            
            av_frame_unref(&frame);
        } //if(avcodec_send_packet)
        
        if (inpkt) av_packet_unref(inpkt);
        if (!inframe) {
            is->video_eof = true;
        }
    }//while(true)
    
    if (is->audio_eof == Player::audio_eof_enum::eof) is->Quit();
    is->video_eof = true;
    return 0;
}

int subtitle_thread(void *arg)
{
    Player *is = (Player *)arg;
    AVPacket packet = { 0 };
    std::shared_ptr<SwsContext> sub_convert_ctx;
    int64_t old_serial = 0;
    
    is->subpictq_active_serial = av_gettime();
    av_log(NULL, AV_LOG_INFO, "subtitle thread start\n");
    while (!is->IsQuit()) {
        AVCodecContext *subtitle_ctx = is->subtitle_ctx.get();
        if (is->subtitleq.get(&packet, 1) < 0) {
            // means we quit getting packets
            av_log(NULL, AV_LOG_INFO, "subtitle Quit\n");
            break;
        }
    retry:
        if (packet.data == flush_pkt.data) {
            av_log(NULL, AV_LOG_INFO, "subtitle buffer flush\n");
            avcodec_flush_buffers(subtitle_ctx);
            packet = { 0 };
            is->subpictq_active_serial = av_gettime();
            continue;
        }
        if (packet.data == eof_pkt.data) {
            av_log(NULL, AV_LOG_INFO, "subtitle buffer EOF\n");
            packet = { 0 };
            while (!is->IsQuit() && is->subtitleq.get(&packet, 0) == 0)
                SDL_Delay(100);
            if (is->IsQuit()) break;
            goto retry;
        }
        if (packet.data == abort_pkt.data) {
            av_log(NULL, AV_LOG_INFO, "subtitle buffer ABORT\n");
            packet = { 0 };
            break;
        }
        int got_frame = 0;
        int ret;
        double pts = 0;
        AVSubtitle sub;
        if ((ret = avcodec_decode_subtitle2(subtitle_ctx, &sub, &got_frame, &packet)) < 0) {
            av_packet_unref(&packet);
            char buf[AV_ERROR_MAX_STRING_SIZE];
            char *errstr = av_make_error_string(buf, AV_ERROR_MAX_STRING_SIZE, ret);
            av_log(NULL, AV_LOG_ERROR, "error avcodec_decode_subtitle2() %d %s\n", ret, errstr);
            return -1;
        }
        if (packet.pts != AV_NOPTS_VALUE)
            pts = packet.pts * av_q2d(is->subtitle_st->time_base);
        av_packet_unref(&packet);
        if (got_frame == 0) continue;
        
        if (sub.pts != AV_NOPTS_VALUE)
            pts = sub.pts / (double)AV_TIME_BASE;
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
        
        for (size_t i = 0; i < sub.num_rects; i++)
        {
            sp->subw = subtitle_ctx->width ? subtitle_ctx->width : is->video_ctx->width;
            sp->subh = subtitle_ctx->height ? subtitle_ctx->height : is->video_ctx->height;
            
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
                if (av_image_alloc(sp->subrects[i]->data, sp->subrects[i]->linesize, sub.rects[i]->w, sub.rects[i]->h, AV_PIX_FMT_ARGB, 16) < 0) {
                    av_log(NULL, AV_LOG_FATAL, "Cannot allocate subtitle data\n");
                    return -1;
                }
                sub_convert_ctx = std::shared_ptr<SwsContext>(sws_getCachedContext(NULL,
                                                                                   sub.rects[i]->w, sub.rects[i]->h, AV_PIX_FMT_PAL8,
                                                                                   sub.rects[i]->w, sub.rects[i]->h, AV_PIX_FMT_ARGB,
                                                                                   SWS_BICUBIC, NULL, NULL, NULL), &sws_freeContext);
                if (!sub_convert_ctx) {
                    av_log(NULL, AV_LOG_FATAL, "Cannot initialize the sub conversion context\n");
                    return -1;
                }
                sws_scale(sub_convert_ctx.get(),
                          sub.rects[i]->data, sub.rects[i]->linesize,
                          0, sub.rects[i]->h, sp->subrects[i]->data, sp->subrects[i]->linesize);
                sp->subrects[i]->w = sub.rects[i]->w;
                sp->subrects[i]->h = sub.rects[i]->h;
                sp->subrects[i]->x = sub.rects[i]->x;
                sp->subrects[i]->y = sub.rects[i]->y;
            }
        }
        is->subpictq.put(sp);
        avsubtitle_free(&sub);
    }
    return 0;
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

int Player::audio_decode_frame(uint8_t *audio_buf, int buf_size, double *pts_ptr)
{
    int buf_limit = buf_size * 3 / 4;
    AVCodecContext *aCodecCtx = audio_ctx.get();
    SwrContext *a_convert_ctx = swr_ctx.get();
    AVPacket pkt = { 0 }, *inpkt = &pkt;
    AVFrame audio_frame_in = { 0 }, *inframe = &audio_frame_in;
    AVFrame audio_frame_out = { 0 };
    
    while(true) {
        int ret;
        if (seek_req) {
            audio_clock = NAN;
            av_log(NULL, AV_LOG_INFO, "seeking audio mute\n");
            goto quit_audio;
        }
        if (inpkt) {
            if ((ret = audioq.get(inpkt, 0)) < 0) {
                av_log(NULL, AV_LOG_INFO, "audio Quit\n");
                audio_eof = audio_eof_enum::eof;
                goto quit_audio;
            }
            if (audio_eof == audio_eof_enum::playing && ret == 0) {
                av_log(NULL, AV_LOG_INFO, "audio queue empty\n");
                goto quit_audio;
            }
            if (inpkt->data == flush_pkt.data) {
                av_log(NULL, AV_LOG_INFO, "audio buffer flush\n");
                avcodec_flush_buffers(aCodecCtx);
                pkt = { 0 };
                audio_serial = av_gettime();
                inpkt = &pkt;
                inframe = &audio_frame_in;
                continue;
            }
            if (inpkt->data == eof_pkt.data) {
                av_log(NULL, AV_LOG_INFO, "audio buffer EOF\n");
                audio_eof = audio_eof_enum::input_eof;
            }
            if (inpkt->data == abort_pkt.data) {
                av_log(NULL, AV_LOG_INFO, "audio buffer ABORT\n");
                audio_eof = audio_eof_enum::eof;
                goto quit_audio;
            }
        }
        if (audio_eof >= audio_eof_enum::input_eof) {
            inpkt = NULL;
            if (audio_eof == audio_eof_enum::output_eof) {
                audio_eof = audio_eof_enum::eof;
                av_log(NULL, AV_LOG_INFO, "audio EOF\n");
                if (video_eof) Quit();
                goto quit_audio;
            }
        }
        
        // send packet to codec context
        ret = avcodec_send_packet(aCodecCtx, inpkt);
        if (ret >= 0 || (audio_eof == audio_eof_enum::input_eof && ret == AVERROR_EOF)) {
            if (inpkt) av_packet_unref(inpkt);
            int data_size = 0;
            
            // Decode audio frame
            while ((ret = avcodec_receive_frame(aCodecCtx, inframe)) >= 0 || ret == AVERROR_EOF) {
                if (ret == AVERROR_EOF)
                    inframe = NULL;
                
                if (inframe) {
                    auto dec_channel_layout = get_valid_channel_layout(inframe->channel_layout, inframe->channels);
                    if (!dec_channel_layout)
                        dec_channel_layout = av_get_default_channel_layout(inframe->channels);
                    bool reconfigure =
                    cmp_audio_fmts(audio_filter_src.fmt, audio_filter_src.channels,
                                   (enum AVSampleFormat)inframe->format, inframe->channels) ||
                    audio_filter_src.channel_layout != dec_channel_layout ||
                    audio_filter_src.freq != inframe->sample_rate ||
                    audio_filter_src.audio_volume_dB != audio_volume_dB ||
                    audio_filter_src.audio_volume_auto != audio_volume_auto ||
                    audio_filter_src.serial != audio_serial;
                    
                    if (reconfigure) {
                        audio_filter_src.fmt = (enum AVSampleFormat)inframe->format;
                        audio_filter_src.channels = inframe->channels;
                        audio_filter_src.channel_layout = dec_channel_layout;
                        audio_filter_src.freq = inframe->sample_rate;
                        audio_filter_src.audio_volume_dB = audio_volume_dB;
                        audio_filter_src.audio_volume_auto = audio_volume_auto;
                        audio_filter_src.serial = audio_serial;
                        
                        if (!configure_audio_filters())
                            goto quit_audio;
                        
                        a_convert_ctx = swr_alloc_set_opts(NULL,
                                                           av_get_default_channel_layout(audio_out_channels), AV_SAMPLE_FMT_S16, audio_out_sample_rate,
                                                           afilt_out->inputs[0]->channel_layout, (enum AVSampleFormat)afilt_out->inputs[0]->format, afilt_out->inputs[0]->sample_rate,
                                                           0, NULL);
                        swr_init(a_convert_ctx);
                        
                        swr_ctx = std::shared_ptr<SwrContext>(a_convert_ctx, [](SwrContext *ptr) { swr_free(&ptr); });
                    }
                }
                
                if (!afilt_in || !afilt_out)
                    goto quit_audio;
                
                if (av_buffersrc_add_frame(afilt_in, inframe) < 0)
                    goto quit_audio;
                
                if (inframe) av_frame_unref(inframe);
                while (buf_size > buf_limit && (ret = av_buffersink_get_frame(afilt_out, &audio_frame_out)) >= 0) {
                    
                    int64_t pts_t;
                    if ((pts_t = audio_frame_out.best_effort_timestamp) != AV_NOPTS_VALUE) {
                        audio_clock = av_q2d(audio_st->time_base)*pts_t;
                        //av_log(NULL, AV_LOG_INFO, "audio clock %f\n", audio_clock);
                        if (isnan(audio_clock_start)) {
                            audio_clock_start = audio_clock;
                        }
                    }
                    
                    int out_samples = (int)av_rescale_rnd(swr_get_delay(a_convert_ctx, audio_frame_out.sample_rate) +
                                                          audio_frame_out.nb_samples, audio_out_sample_rate, audio_frame_out.sample_rate, AV_ROUND_UP);
                    int out_size = av_samples_get_buffer_size(NULL,
                                                              audio_out_channels,
                                                              out_samples,
                                                              AV_SAMPLE_FMT_S16,
                                                              1);
                    assert(out_size <= buf_size);
                    swr_convert(a_convert_ctx, &audio_buf, out_samples, (const uint8_t **)audio_frame_out.data, audio_frame_out.nb_samples);
                    audio_buf += out_size;
                    buf_size -= out_size;
                    data_size += out_size;
                    
                    int n = 2 * audio_out_channels;
                    audio_clock += (double)out_size /
                    (double)(n * audio_out_sample_rate);
                    
                    av_frame_unref(&audio_frame_out);
                }//while(av_buffersink_get_frame)
                
                if (ret == AVERROR_EOF) {
                    audio_eof = audio_eof_enum::output_eof;
                    av_log(NULL, AV_LOG_INFO, "audio output EOF\n");
                }
                
                if (!inframe) break;
            }//while(avcodec_receive_frame)
            
            if (data_size > 0) {
                double pts = audio_clock;
                *pts_ptr = pts;
                /* We have data, return it and come back for more later */
                return data_size;
            }
        } //if (avcodec_send_packet)
        if(inpkt) av_packet_unref(inpkt);
        
        if (IsQuit()) {
            goto quit_audio;
        }
    }//while(true)
quit_audio:
    av_log(NULL, AV_LOG_INFO, "audio Pause\n");
    SDL_PauseAudioDevice(audio_deviceID, 1);
    audio_pause = true;
    return -1;
}

void Player::video_refresh_timer()
{
    update_info(((struct stream_param *)param)->stream, (pause) ? 0 : 1, playtime, duration);
    
    if (video_st && force_draw) {
        force_draw = false;
        video_display(pictq_prev);
        return;
    }
    
    if( --remove_refresh > 0) {
        return;
    }
    
    if (audio_only) {
        set_clockduration(get_audio_clock());
        if (!ishidden) {
            audioonly_video_display();
        }
        schedule_refresh(100);
        return;
    }
    if (!video_st) {
        loading_display();
        schedule_refresh(100);
        return;
    }
    
    VideoPicture *vp = &pictq[pictq_rindex];
    if(!vp->allocated) {
        loading_display();
        schedule_refresh(100);
        return;
    }
    while (vp->serial < pictq_active_serial && pictq_size > 0) {
        vp = next_picture_queue();
        frame_last_pts = NAN;
    }

    if (change_pause) {
        change_pause = false;
        frame_timer = NAN;
    }
    
    if (seek_req) {
        schedule_refresh(100);
        pict_seek_after = true;
        frame_timer = NAN;
        return;
    }
    
    if (!video_only && (isnan(audio_clock) || (audio_eof != audio_eof_enum::eof && audio_pause))) {
        loading_display();
        schedule_refresh(100);
        frame_timer = NAN;
        return;
    }
    
    if (pictq_size == 0) {
        schedule_refresh(1);
        return;
    }

    if (pause) {
        video_display(pictq_prev);
        schedule_refresh(100);
        return;
    }
    
    while (pictq_size > 0)
    {
        if (isnan(frame_timer)) {
            frame_timer = (double)av_gettime() / 1000000.0;
        }
        
        if (pict_seek_after && !sync_video) {
            double ref_clock = get_master_clock();
            double diff = vp->pts - ref_clock;

            diff += audio_sync_delay;

            if (diff < 0) {
                vp = next_picture_queue();
                continue;
            }
        }
        
        pict_seek_after = false;
        video_current_pts = vp->pts;
        video_current_pts_time = av_gettime();
        set_clockduration(vp->pts);
        
        double delay = vp->pts - frame_last_pts; /* the pts from last time */
        if (delay >= -1.0 && delay <= 1.0) {
            // use original
        }
        else {
            /* if incorrect delay, use previous one */
            delay = frame_last_delay;
        }
        /* save for next time */
        frame_last_pts = vp->pts;
        
        /* update delay to sync to audio if not master source */
        if (!sync_video) {
            double ref_clock = get_master_clock();
            double diff = vp->pts - ref_clock;

            diff += audio_sync_delay;
            
            diff += (audio_callback_time - av_gettime() / 1000000.0);
            video_delay_to_audio = diff;
            /* Skip or repeat the frame. Take delay into account
             FFPlay still doesn't "know if this is the best guess." */
            double sync_threshold = (delay > AV_SYNC_THRESHOLD) ? delay : AV_SYNC_THRESHOLD;
            if (fabs(diff) < AV_NOSYNC_THRESHOLD) {
                if (diff <= -sync_threshold) {
                    delay = (diff + delay < 0)? 0: diff + delay;
                }
                else if (diff >= sync_threshold && delay > AV_SYNC_FRAMEDUP_THRESHOLD) {
                    delay = diff + delay;
                }
                else if (diff >= sync_threshold * 2) {
                    delay = 2 * delay;
                }
                else if (diff >= sync_threshold) {
                    delay = (diff / sync_threshold) * delay;
                }
            }
        }
        if (delay >= -1.0 && delay <= 1.0) {
            frame_last_delay = (frame_last_delay * 9 + delay * 1) / 10;
        }
        
        
        frame_timer += delay;
        /* computer the REAL delay */
        double actual_delay = frame_timer - av_gettime() / 1000000.0;
        
        if (fabs(actual_delay) > AV_NOSYNC_THRESHOLD) {
            frame_timer += actual_delay;
        }
        else if (actual_delay > AV_SYNC_THRESHOLD) {
            schedule_refresh((int)((actual_delay - AV_SYNC_THRESHOLD) * 1000));
        }

        /* show the picture! */
        if (!ishidden) {
            video_display(vp);
        }
        vp = next_picture_queue();
        
        if (remove_refresh > 0)
            return;
    }
    if(remove_refresh == 0)
        schedule_refresh(1);
}

void Player::loading_display()
{
    SDL_LockMutex(screen_mutex.get());
    {
        SDL_Color textColor = { 255, 255, 255, 0 };
        char loadtext[] = "Now loading....";
        int i = (av_gettime() / 1000000) % 4;
        loadtext[strlen(loadtext)-(3-i)] = '\0';
        SDL_Surface *textSurface = TTF_RenderText_Blended(font, loadtext, textColor);
        SDL_Texture *text = SDL_CreateTextureFromSurface(renderer, textSurface);
        int text_width = textSurface->w;
        int text_height = textSurface->h;

        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        SDL_RenderClear(renderer);
        
        int tmp_w, tmp_h;
        SDL_GetRendererOutputSize(renderer, &tmp_w, &tmp_h);
        if (rotate_lock && tmp_h > tmp_w) {
            int x = (tmp_w - text_width) / 2;
            int y = (tmp_h - text_height) / 2;
            SDL_Rect renderQuad = { x, y, text_width, text_height };
            
            SDL_RenderCopyEx(renderer, text, NULL, &renderQuad, 90, NULL, SDL_FLIP_NONE);
        }
        else {
            int x = (tmp_w - text_width) / 2;
            int y = (tmp_h - text_height) / 2;
            SDL_Rect renderQuad = { x, y, text_width, text_height };
            
            SDL_RenderCopy(renderer, text, NULL, &renderQuad);
        }
        overlay_info();
        SDL_RenderPresent(renderer);
    }
    SDL_UnlockMutex(screen_mutex.get());
}

void Player::video_display(VideoPicture *vp)
{
    if (vp->allocated) {
        SDL_Rect rect;
        SDL_Rect rectsrc;
        double aspect_ratio;
        int w, h, x, y;
        
        rectsrc.x = 0;
        rectsrc.y = 0;
        rectsrc.w = vp->width;
        rectsrc.h = vp->height;
        
        if (video_ctx->sample_aspect_ratio.num == 0) {
            aspect_ratio = 0;
        }
        else {
            aspect_ratio = av_q2d(video_ctx->sample_aspect_ratio) *
            video_ctx->width / video_ctx->height;
        }
        if (aspect_ratio <= 0.0) {
            aspect_ratio = (double)video_ctx->width /
            (double)video_ctx->height;
        }
        SDL_LockMutex(screen_mutex.get());
        {
            int tmp_w, tmp_h;
            SDL_GetRendererOutputSize(renderer, &tmp_w, &tmp_h);
            if (rotate_lock && ((aspect_ratio > 1 && tmp_h > tmp_w) || (aspect_ratio < 1 && tmp_w > tmp_h))) {
                h = tmp_w;
                w = ((int)rint(h * aspect_ratio)) & ~1;
                if (w > tmp_h) {
                    w = tmp_h;
                    h = ((int)rint(w / aspect_ratio)) & ~1;
                }
                y = (tmp_h - h) / 2;
                x = (tmp_w - w) / 2;
                turn = true;
            }
            else {
                h = tmp_h;
                w = ((int)rint(h * aspect_ratio)) & ~1;
                if (w > tmp_w) {
                    w = tmp_w;
                    h = ((int)rint(w / aspect_ratio)) & ~1;
                }
                y = (tmp_h - h) / 2;
                x = (tmp_w - w) / 2;
                turn = false;
            }
            rect.x = x;
            rect.y = y;
            rect.w = w;
            rect.h = h;

            void *pixels = NULL;
            int pitch = 0;
            SDL_LockTexture(texture.get(), NULL, &pixels, &pitch);
            if (pitch != vp->bmp.linesize[0]) {
                int srcpitch = vp->bmp.linesize[0];
                for (int y = 0; y < vp->height; y++)
                    memcpy((uint8_t *)pixels + pitch*y, &vp->bmp.data[0][y*srcpitch], pitch);
            }
            else {
                memcpy(pixels, vp->bmp.data[0], pitch*vp->height);
            }
            if (pitch / 2 != vp->bmp.linesize[2]) {
                int srcpitch = vp->bmp.linesize[2];
                uint8_t* dst = (uint8_t *)pixels + pitch*vp->height;
                for (int y = 0; y < vp->height / 2; y++)
                    memcpy(dst + pitch*y / 2, &vp->bmp.data[2][y*srcpitch], pitch / 2);
            }
            else {
                memcpy((uint8_t *)pixels + pitch*vp->height, vp->bmp.data[2], pitch*vp->height / 4);
            }
            if (pitch / 2 != vp->bmp.linesize[1]) {
                int srcpitch = vp->bmp.linesize[1];
                uint8_t* dst = (uint8_t *)pixels + pitch*vp->height * 5 / 4;
                for (int y = 0; y < vp->height / 2; y++)
                    memcpy(dst + pitch*y / 2, &vp->bmp.data[1][y*srcpitch], pitch / 2);
            }
            else {
                memcpy((uint8_t *)pixels + pitch*vp->height * 5 / 4, vp->bmp.data[1], pitch*vp->height / 4);
            }
            SDL_UnlockTexture(texture.get());
            SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
            SDL_RenderClear(renderer);
            if (turn) {
                SDL_RenderCopyEx(renderer, texture.get(), NULL, &rect, 90, NULL, SDL_FLIP_NONE);
            }
            else {
                SDL_RenderCopy(renderer, texture.get(), NULL, &rect);
            }
            if (subtitleStream >= 0)
                subtitle_display(vp->pts);
            overlay_txt(vp);
            overlay_info();
            SDL_RenderPresent(renderer);
        }
        SDL_UnlockMutex(screen_mutex.get());
    }
}

void Player::audioonly_video_display()
{
    SDL_Rect rect;
    double aspect_ratio;
    int w, h, x, y;
    
    turn = false;
    if (statictexture != NULL) {
        SDL_QueryTexture(statictexture.get(), NULL, NULL, &w, &h);
        
        aspect_ratio = (double)w / (double)h;
        int tmp_w, tmp_h;
        SDL_GetRendererOutputSize(renderer, &tmp_w, &tmp_h);
        h = tmp_h;
        w = ((int)rint(h * aspect_ratio)) & ~1;
        if (w > tmp_w) {
            w = tmp_w;
            h = ((int)rint(w / aspect_ratio)) & ~1;
        }
        y = (tmp_h - h) / 2;
        x = (tmp_w - w) / 2;
        
        rect.x = x;
        rect.y = y;
        rect.w = w;
        rect.h = h;
    }
    SDL_LockMutex(screen_mutex.get());
    {
        SDL_RenderClear(renderer);
        if (statictexture != NULL)
            SDL_RenderCopy(renderer, statictexture.get(), NULL, &rect);
        
        overlay_txt(get_audio_clock());
        overlay_info();
        SDL_RenderPresent(renderer);
    }
    SDL_UnlockMutex(screen_mutex.get());
}

void Player::subtitle_display(double pts)
{
    std::shared_ptr<SubtitlePicture> sp;
    if (subpictq.get(pts, sp) == 0) {

        int tmp_w, tmp_h;
        SDL_GetRendererOutputSize(renderer, &tmp_w, &tmp_h);
        int w_size;
        if (turn) {
            w_size = tmp_h;
        }
        else {
            w_size = tmp_w;
        }
        
        if (sp->type == 0) {
            if (sp->serial != subserial || subwidth != w_size) {
                if (subtitlelen != sp->numrects) {
                    subtitle.reset(new std::shared_ptr<SDL_Texture>[sp->numrects]);
                    subtitlelen = sp->numrects;
                }
                {
                    for (int i = 0; i < sp->numrects; i++) {
                        int w = 0, h = 0;
                        if(subtitle[i].get() != NULL)
                            SDL_QueryTexture(subtitle[i].get(), NULL, NULL, &w, &h);
                        if (w != sp->subrects[i]->w || h != sp->subrects[i]->h) {
                            subtitle[i] = std::shared_ptr<SDL_Texture>(SDL_CreateTexture(
                                                                                         renderer,
                                                                                         SDL_PIXELFORMAT_BGRA8888,
                                                                                         SDL_TEXTUREACCESS_STREAMING,
                                                                                                 sp->subrects[i]->w,
                                                                                                 sp->subrects[i]->h),
                                                                               &SDL_DestroyTexture);
                            SDL_SetTextureBlendMode(subtitle[i].get(), SDL_BLENDMODE_BLEND);
                        }
                    }
                }
                for (int i = 0; i < sp->numrects; i++) {
                    void *pixels = NULL;
                    int pitch = 0;
                    int h = sp->subrects[i]->h;
                    SDL_LockTexture(subtitle[i].get(), NULL, &pixels, &pitch);
                    if (sp->subrects[i]->linesize[0] != pitch) {
                        uint8_t *dst = (uint8_t*)pixels;
                        int srcpitch = sp->subrects[i]->linesize[0];
                        for (int y = 0; y < h; y++) {
                            memcpy(dst, &sp->subrects[i]->data[0][srcpitch*y], pitch);
                            dst += pitch;
                        }
                    }
                    else {
                        memcpy(pixels, sp->subrects[i]->data[0], pitch*h);
                    }
                    SDL_UnlockTexture(subtitle[i].get());
                }
                subserial = sp->serial;
                subwidth = w_size;
            }
            for (int i = 0; i < sp->numrects; i++) {
                int in_w = sp->subrects[i]->w;
                int in_h = sp->subrects[i]->h;
                int subw = sp->subw ? sp->subw : video_ctx->width;
                int subh = sp->subh ? sp->subh : video_ctx->height;
                int screenw = (turn)? tmp_h: tmp_w;
                int screenh = (turn)? tmp_w: tmp_h;
                int out_w = screenw ? (in_w * screenw / subw) & ~1 : in_w;
                int out_h = screenh ? (in_h * screenh / subh) & ~1 : in_h;
                out_w = (out_w) ? out_w : subw;
                out_h = (out_h) ? out_h : subh;
                
                if (turn) {
                    SDL_Rect rect = {
                        tmp_w - ((in_h) ? sp->subrects[i]->y * out_h / in_h : sp->subrects[i]->y),
                        ((in_w) ? sp->subrects[i]->x * out_w / in_w : sp->subrects[i]->x),
                        out_w,
                        out_h
                    };
                    SDL_Point p = { 0, 0 };
                    SDL_RenderCopyEx(renderer, subtitle[i].get(), NULL, &rect, 90, &p, SDL_FLIP_NONE);
                }
                else {
                    SDL_Rect rect = {
                        (in_w) ? sp->subrects[i]->x * out_w / in_w : sp->subrects[i]->x,
                        (in_h) ? sp->subrects[i]->y * out_h / in_h : sp->subrects[i]->y,
                        out_w,
                        out_h
                    };
                    SDL_RenderCopy(renderer, subtitle[i].get(), NULL, &rect);
                }
            }
        }
        else {
            if (subtitlelen != sp->numrects) {
                subtitle.reset(new std::shared_ptr<SDL_Texture>[sp->numrects]);
                subtitlelen = sp->numrects;
            }
            if (sp->serial != subserial || subwidth != w_size) {
                subserial = sp->serial;
                subwidth = w_size;
                int x = 0, y = 0;
                for (int i = 0; i < sp->numrects; i++) {
                    if (sp->subrects[i]->text) {
                        SDL_Color textColor = { 255, 255, 255, 0 };
                        char *t = sp->subrects[i]->text;
                        std::shared_ptr<SDL_Surface> textSurface(TTF_RenderUTF8_Blended_Wrapped(font, t, textColor, subwidth), &SDL_FreeSurface);
                        subtitle[i] = std::shared_ptr<SDL_Texture>(SDL_CreateTextureFromSurface(renderer, textSurface.get()), &SDL_DestroyTexture);
                        sp->subrects[i]->x = x;
                        sp->subrects[i]->y = y;
                        sp->subrects[i]->w = textSurface->w;
                        sp->subrects[i]->h = textSurface->h;
                        y += sp->subrects[i]->h;
                    }
                    if (sp->subrects[i]->ass) {
                        auto textSurface = subtitle_ass(sp->subrects[i]->ass);
                        if (textSurface == NULL) continue;
                        subtitle[i] = std::shared_ptr<SDL_Texture>(SDL_CreateTextureFromSurface(renderer, textSurface.get()), &SDL_DestroyTexture);
                        sp->subrects[i]->x = x;
                        sp->subrects[i]->y = y;
                        sp->subrects[i]->w = textSurface->w;
                        sp->subrects[i]->h = textSurface->h;
                        y += sp->subrects[i]->h;
                    }
                }
                int height = (turn)? tmp_w: tmp_h;
                for (int i = 0; i < sp->numrects; i++) {
                    sp->subrects[i]->y += height - y;
                }
            }
            for (int i = 0; i < sp->numrects; i++) {
                if (turn) {
                    SDL_Rect renderQuad = { tmp_w - sp->subrects[i]->y - sp->subrects[i]->w/2, sp->subrects[i]->x - sp->subrects[i]->h/2 + sp->subrects[i]->w/2, sp->subrects[i]->w, sp->subrects[i]->h };
                    SDL_RenderCopyEx(renderer, subtitle[i].get(), NULL, &renderQuad, 90, NULL, SDL_FLIP_NONE);
                }
                else {
                    SDL_Rect renderQuad = { sp->subrects[i]->x, sp->subrects[i]->y, sp->subrects[i]->w ,  sp->subrects[i]->h };
                    SDL_RenderCopy(renderer, subtitle[i].get(), NULL, &renderQuad);
                }
            }
        }
    }
}

std::shared_ptr<SDL_Surface> Player::subtitle_ass(const char *text)
{
    SDL_Color textColor = { 255, 255, 255, 0 };
    std::string txt(text);
    std::list<std::string> txtlist;
    std::string::size_type p, pos = 0;
    std::list<std::string> direction;
    
    if ((p = txt.find(':', pos)) == std::string::npos) return NULL;
    direction.push_back(txt.substr(pos, p - pos));
    pos = p + 1;
    
    for (int i = 0; i < 9; i++) {
        if ((p = txt.find(',', pos)) == std::string::npos) return NULL;
        direction.push_back(txt.substr(pos, p - pos));
        pos = p + 1;
    }
    txt = txt.substr(pos);
    p = pos = 0;
    for (size_t i = 0; i < txt.length(); i++) {
        if (txt[i] == '{' && i < txt.length() - 1 && txt[i + 1] == '\\') {
            // command
            pos = i+2;
            if ((p = txt.find('}', pos)) == std::string::npos) return NULL;
            std::string command = txt.substr(pos, p - pos);
            i = p;
            pos = p + 1;
            continue;
        }
        if (txt[i] == '\\' && i < txt.length() - 1 && (txt[i + 1] == 'N' || txt[i + 1] == 'n')) {
            txtlist.push_back(txt.substr(pos, i));
            pos = i + 2;
            i++;
            continue;
        }
    }
    txtlist.push_back(txt.substr(pos));
    
    std::list<std::shared_ptr<SDL_Surface>> txtSurfacelist;
    int h = 0, w = 0;
    for (auto t : txtlist) {
        std::shared_ptr<SDL_Surface> txtsf(TTF_RenderUTF8_Blended_Wrapped(font, t.c_str(), textColor, subwidth), &SDL_FreeSurface);
        txtSurfacelist.push_back(txtsf);
        h += txtsf->h;
        w = (w > txtsf->w) ? w : txtsf->w;
    }
    Uint32 rmask, gmask, bmask, amask;
    rmask = 0x000000ff;
    gmask = 0x0000ff00;
    bmask = 0x00ff0000;
    amask = 0xff000000;
    std::shared_ptr<SDL_Surface> textSurface(SDL_CreateRGBSurface(0, w, h, 32, rmask, gmask, bmask, amask), &SDL_FreeSurface);
    SDL_FillRect(textSurface.get(), NULL, SDL_MapRGBA(textSurface->format, 0, 0, 0, 128));
    int xx = 0, yy = 0;
    for (auto t : txtSurfacelist) {
        SDL_Rect rect = { xx, yy, t->w, t->h };
        SDL_BlitSurface(t.get(), NULL, textSurface.get(), &rect);
        yy += t->h;
    }
    return textSurface;
}

void Player::overlay_txt(VideoPicture *vp) {
    overlay_txt(vp->pts);
}

void Player::overlay_txt(double pts)
{
    if (start_time_org != AV_NOPTS_VALUE){
        if (pts - start_time_org / 1000000.0 >((int64_t)1 << 32) / 90000.0) {
            pts_rollover = true;
        }
    }
    if (isnan(pts)) return;
    
    char out_text[1024];
    if (overlay_text.empty()) {
        double ns;
        int hh, mm, ss;
        int tns, thh, tmm, tss;
        
        pos_ratio = get_duration();
        tns = (int)pos_ratio;
        thh = tns / 3600;
        tmm = (tns % 3600) / 60;
        tss = (tns % 60);
        ns = pts;
        if (start_time_org != AV_NOPTS_VALUE){
            if (pts - start_time_org / 1000000.0 >((int64_t)1 << 32) / 90000.0) {
                ns -= ((int64_t)1 << 33) / 90000.0;
            }
            ns -= start_time_org / 1000000.0;
        }
        else if (!isnan(video_clock_start))
            ns -= video_clock_start / 1000000.0;
        else if (!isnan(audio_clock_start))
            ns -= audio_clock_start / 1000000.0;
        pos_ratio = ns / pos_ratio;
        hh = (int)(ns) / 3600;
        mm = ((int)(ns) % 3600) / 60;
        ss = ((int)(ns) % 60);
        ns -= (int)(ns);
        sprintf(out_text, "%2d:%02d:%02d.%03d/%2d:%02d:%02d",
                hh, mm, ss, (int)(ns * 1000), thh, tmm, tss);
    }

    if (!display_on && overlay_text.empty()) return;

    int tmp_w, tmp_h;
    SDL_GetRendererOutputSize(renderer, &tmp_w, &tmp_h);

    SDL_SetRenderDrawBlendMode(renderer, SDL_BlendMode::SDL_BLENDMODE_BLEND);
    if (turn){
        SDL_SetRenderDrawColor(renderer, 32, 32, 32, 100);
        SDL_Rect rect2 = { 0, 0, 80, tmp_h };
        SDL_RenderFillRect(renderer, &rect2);
        SDL_SetRenderDrawColor(renderer, 32, 32, 255, 150);
        SDL_Rect rect = { 0, 0, 80, (int)(tmp_h * pos_ratio) };
        SDL_RenderFillRect(renderer, &rect);
    }
    else {
        SDL_SetRenderDrawColor(renderer, 32, 32, 32, 100);
        SDL_Rect rect2 = { 0, tmp_h - 80, tmp_w, 80 };
        SDL_RenderFillRect(renderer, &rect2);
        SDL_SetRenderDrawColor(renderer, 32, 32, 255, 150);
        SDL_Rect rect = { 0, tmp_h - 80, (int)(tmp_w * pos_ratio), 80 };
        SDL_RenderFillRect(renderer, &rect);
    }
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
    SDL_SetRenderDrawBlendMode(renderer, SDL_BlendMode::SDL_BLENDMODE_NONE);
    
    SDL_Color textColor = { 0, 255, 0, 0 };
    std::shared_ptr<SDL_Surface> textSurface(TTF_RenderText_Blended(font, (overlay_text.empty()) ? out_text : overlay_text.c_str(), textColor), &SDL_FreeSurface);
    std::shared_ptr<SDL_Texture> text(SDL_CreateTextureFromSurface(renderer, textSurface.get()), &SDL_DestroyTexture);
    int text_width = textSurface->w;
    int text_height = textSurface->h;
    if (turn) {
        if (text_width > tmp_h / 2) {
            double scale = tmp_h / 2.0 / text_width;
            text_width = (int)(scale * text_width);
            text_height = (int)(scale * text_height);
        }
        int y = (tmp_h - text_height) / 2;
        int x = (text_height - text_width) / 2;

        SDL_Rect renderQuad = { x, y, text_width, text_height };
        SDL_RenderCopyEx(renderer, text.get(), NULL, &renderQuad, 90, NULL, SDL_FLIP_NONE);
    }
    else {
        if (text_width > tmp_w / 2) {
            double scale = tmp_w / 2.0 / text_width;
            text_width = (int)(scale * text_width);
            text_height = (int)(scale * text_height);
        }
        int x = (tmp_w - text_width) / 2;
        int y = tmp_h - text_height;
        x -= x % 50;
        SDL_Rect renderQuad = { x, y, text_width, text_height };
        SDL_RenderCopy(renderer, text.get(), NULL, &renderQuad);
    }
}

void Player::overlay_info()
{
    if (!display_on) return;

    int tmp_w, tmp_h;
    SDL_GetRendererOutputSize(renderer, &tmp_w, &tmp_h);
    
    SDL_SetRenderDrawBlendMode(renderer, SDL_BlendMode::SDL_BLENDMODE_BLEND);
    if (turn){
        SDL_SetRenderDrawColor(renderer, 255, 32, 32, 100);
        SDL_Rect rect2 = { tmp_w - 100, 0, 100, 100 };
        SDL_RenderFillRect(renderer, &rect2);
        SDL_SetRenderDrawColor(renderer, 255, 255, 255, 200);
        SDL_RenderDrawLine(renderer, tmp_w - 100, 0, tmp_w, 100);
        SDL_RenderDrawLine(renderer, tmp_w, 0, tmp_w - 100, 100);
        SDL_SetRenderDrawColor(renderer, 32, 32, 32, 150);
        SDL_Rect rect1 = { tmp_w - 100, 100, 100, tmp_h - 100 };
        SDL_RenderFillRect(renderer, &rect1);

        SDL_Rect rect3 = { tmp_w * 2 / 6, 100, 100, 100 };
        SDL_RenderFillRect(renderer, &rect3);
        SDL_Rect rect4 = { tmp_w * 3 / 6, 100, 100, 100 };
        SDL_RenderFillRect(renderer, &rect4);
        SDL_Rect rect5 = { tmp_w * 4 / 6, 100, 100, 100 };
        SDL_RenderFillRect(renderer, &rect5);

        SDL_Color textColor = { 255, 255, 255, 255 };
        {
            std::shared_ptr<SDL_Surface> textSurface(TTF_RenderUTF8_Blended(font, name.c_str(), textColor), &SDL_FreeSurface);
            std::shared_ptr<SDL_Texture> text(SDL_CreateTextureFromSurface(renderer, textSurface.get()), &SDL_DestroyTexture);
            int text_width = textSurface->w;
            int text_height = textSurface->h;
            if (text_width > tmp_h - 100) {
                double scale = (tmp_h - 100.0) / text_width;
                text_width = (int)(scale * text_width);
                text_height = (int)(scale * text_height);
            }
            SDL_Rect renderQuad = { tmp_w - 50 - text_width/2, (tmp_h - 100)/2 + 100 - text_height/2, text_width, text_height};
            SDL_RenderCopyEx(renderer, text.get(), NULL, &renderQuad, 90, NULL, SDL_FLIP_NONE);
        }
        {
            std::shared_ptr<SDL_Surface> textSurface(TTF_RenderText_Blended(font, "S", textColor), &SDL_FreeSurface);
            std::shared_ptr<SDL_Texture> text(SDL_CreateTextureFromSurface(renderer, textSurface.get()), &SDL_DestroyTexture);
            int text_width = textSurface->w;
            int text_height = textSurface->h;
            SDL_Rect renderQuad = { tmp_w * 2 / 6 + 50 - text_width/2, 150 - text_height/2, text_width, text_height};
            SDL_RenderCopyEx(renderer, text.get(), NULL, &renderQuad, 90, NULL, SDL_FLIP_NONE);
        }
        {
            std::shared_ptr<SDL_Surface> textSurface(TTF_RenderText_Blended(font, "V", textColor), &SDL_FreeSurface);
            std::shared_ptr<SDL_Texture> text(SDL_CreateTextureFromSurface(renderer, textSurface.get()), &SDL_DestroyTexture);
            int text_width = textSurface->w;
            int text_height = textSurface->h;
            SDL_Rect renderQuad = { tmp_w * 3 / 6 + 50 - text_width/2, 150 - text_height/2, text_width, text_height};
            SDL_RenderCopyEx(renderer, text.get(), NULL, &renderQuad, 90, NULL, SDL_FLIP_NONE);
        }
        {
            std::shared_ptr<SDL_Surface> textSurface(TTF_RenderText_Blended(font, "T", textColor), &SDL_FreeSurface);
            std::shared_ptr<SDL_Texture> text(SDL_CreateTextureFromSurface(renderer, textSurface.get()), &SDL_DestroyTexture);
            int text_width = textSurface->w;
            int text_height = textSurface->h;
            SDL_Rect renderQuad = { tmp_w * 4 / 6 + 50 - text_width/2, 150 - text_height/2, text_width, text_height};
            SDL_RenderCopyEx(renderer, text.get(), NULL, &renderQuad, 90, NULL, SDL_FLIP_NONE);
        }
        
        SDL_SetRenderDrawColor(renderer, 32, 32, 32, 150);
        SDL_Rect rect_image1 = { 150, tmp_h / 2 - 50, 100, 100 };
        SDL_RenderFillRect(renderer, &rect_image1);
        SDL_RenderCopyEx(renderer, (pause)?image1.get():image2.get(), NULL, &rect_image1, 90, NULL, SDL_FLIP_NONE);
        SDL_Rect rect_image3 = { 150, tmp_h / 2 - 200, 100, 100 };
        SDL_RenderFillRect(renderer, &rect_image3);
        SDL_RenderCopyEx(renderer, image3.get(), NULL, &rect_image3, 90, NULL, SDL_FLIP_NONE);
        SDL_Rect rect_image4 = { 150, tmp_h / 2 + 100, 100, 100 };
        SDL_RenderFillRect(renderer, &rect_image4);
        SDL_RenderCopyEx(renderer, image4.get(), NULL, &rect_image4, 90, NULL, SDL_FLIP_NONE);
    }
    else {
        SDL_SetRenderDrawColor(renderer, 255, 32, 32, 100);
        SDL_Rect rect2 = { 0, 0, 100, 100 };
        SDL_RenderFillRect(renderer, &rect2);
        SDL_SetRenderDrawColor(renderer, 255, 255, 255, 200);
        SDL_RenderDrawLine(renderer, 0, 0, 100, 100);
        SDL_RenderDrawLine(renderer, 0, 100, 100, 0);
        SDL_SetRenderDrawColor(renderer, 32, 32, 32, 150);
        SDL_Rect rect1 = { 100, 0, tmp_w - 100, 100 };
        SDL_RenderFillRect(renderer, &rect1);

        SDL_Rect rect3 = { 100, tmp_h * 2 / 6, 100, 100 };
        SDL_RenderFillRect(renderer, &rect3);
        SDL_Rect rect4 = { 100, tmp_h * 3 / 6, 100, 100 };
        SDL_RenderFillRect(renderer, &rect4);
        SDL_Rect rect5 = { 100, tmp_h * 4 / 6, 100, 100 };
        SDL_RenderFillRect(renderer, &rect5);
        

        SDL_Color textColor = { 255, 255, 255, 255 };
        {
            std::shared_ptr<SDL_Surface> textSurface(TTF_RenderUTF8_Blended(font, name.c_str(), textColor), &SDL_FreeSurface);
            std::shared_ptr<SDL_Texture> text(SDL_CreateTextureFromSurface(renderer, textSurface.get()), &SDL_DestroyTexture);
            int text_width = textSurface->w;
            int text_height = textSurface->h;
            if (text_width > tmp_w - 100) {
                double scale = (tmp_w - 100.0) / text_width;
                text_width = (int)(scale * text_width);
                text_height = (int)(scale * text_height);
            }
            SDL_Rect renderQuad = { 100 + (tmp_w - 100)/2 - text_width/2, 50 - text_height / 2, text_width, text_height};
            SDL_RenderCopy(renderer, text.get(), NULL, &renderQuad);
        }
        {
            std::shared_ptr<SDL_Surface> textSurface(TTF_RenderText_Blended(font, "S", textColor), &SDL_FreeSurface);
            std::shared_ptr<SDL_Texture> text(SDL_CreateTextureFromSurface(renderer, textSurface.get()), &SDL_DestroyTexture);
            int text_width = textSurface->w;
            int text_height = textSurface->h;
            SDL_Rect renderQuad = { 150 - text_width/2, tmp_h * 4 / 6 + 50 - text_height/2, text_width, text_height};
            SDL_RenderCopy(renderer, text.get(), NULL, &renderQuad);
        }
        {
            std::shared_ptr<SDL_Surface> textSurface(TTF_RenderText_Blended(font, "V", textColor), &SDL_FreeSurface);
            std::shared_ptr<SDL_Texture> text(SDL_CreateTextureFromSurface(renderer, textSurface.get()), &SDL_DestroyTexture);
            int text_width = textSurface->w;
            int text_height = textSurface->h;
            SDL_Rect renderQuad = { 150 - text_width/2, tmp_h * 3 / 6 + 50 - text_height/2, text_width, text_height};
            SDL_RenderCopy(renderer, text.get(), NULL, &renderQuad);
        }
        {
            std::shared_ptr<SDL_Surface> textSurface(TTF_RenderText_Blended(font, "T", textColor), &SDL_FreeSurface);
            std::shared_ptr<SDL_Texture> text(SDL_CreateTextureFromSurface(renderer, textSurface.get()), &SDL_DestroyTexture);
            int text_width = textSurface->w;
            int text_height = textSurface->h;
            SDL_Rect renderQuad = { 150 - text_width/2, tmp_h * 2 / 6 + 50 - text_height/2, text_width, text_height};
            SDL_RenderCopy(renderer, text.get(), NULL, &renderQuad);
        }


        SDL_SetRenderDrawColor(renderer, 32, 32, 32, 150);
        SDL_Rect rect_image1 = { tmp_w / 2 - 50, tmp_h - 250, 100, 100 };
        SDL_RenderFillRect(renderer, &rect_image1);
        SDL_RenderCopy(renderer, (pause)?image1.get():image2.get(), NULL, &rect_image1);
        SDL_Rect rect_image3 = { tmp_w / 2 - 200, tmp_h - 250, 100, 100 };
        SDL_RenderFillRect(renderer, &rect_image3);
        SDL_RenderCopy(renderer, image3.get(), NULL, &rect_image3);
        SDL_Rect rect_image4 = { tmp_w / 2 + 100, tmp_h - 250, 100, 100 };
        SDL_RenderFillRect(renderer, &rect_image4);
        SDL_RenderCopy(renderer, image4.get(), NULL, &rect_image4);
    }
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
    SDL_SetRenderDrawBlendMode(renderer, SDL_BlendMode::SDL_BLENDMODE_NONE);

}

int Player::queue_picture(AVFrame *pFrame, double pts)
{
    VideoPicture *vp;
    
    /* wait until we have space for a new pic */
    SDL_LockMutex(pictq_mutex.get());
    while (!IsQuit() && pictq_size >= VIDEO_PICTURE_QUEUE_SIZE-1) {
        SDL_CondWait(pictq_cond.get(), pictq_mutex.get());
    }
    SDL_UnlockMutex(pictq_mutex.get());
    
    if (IsQuit())
        return -1;
    
    // windex is set to 0 initially
    vp = &pictq[pictq_windex];
    
    int width = video_width;
    int height = video_height;
    
    /* allocate or resize the buffer! */
    if (!vp->allocated ||
        vp->width != width ||
        vp->height != height) {
        
        vp->Allocate(width, height);
        if (IsQuit()) {
            return -1;
        }
    }
    
    /* We have a place to put our picture on the queue */
    // Convert the image into YUV format that SDL uses
    sws_scale(sws_ctx.get(), pFrame->data,
              pFrame->linesize, 0, pFrame->height,
              vp->bmp.data, vp->bmp.linesize);
    
    vp->pts = pts;
    vp->serial = av_gettime();
    
    /* now we inform our display thread that we have a pic ready */
    if (++pictq_windex == VIDEO_PICTURE_QUEUE_SIZE) {
        pictq_windex = 0;
    }
    SDL_LockMutex(pictq_mutex.get());
    pictq_size++;
    SDL_UnlockMutex(pictq_mutex.get());
    return 0;
}

VideoPicture *Player::next_picture_queue()
{
    pictq_prev = &pictq[pictq_rindex];
    /* update queue for next picture! */
    if (++pictq_rindex == VIDEO_PICTURE_QUEUE_SIZE) {
        pictq_rindex = 0;
    }
    SDL_LockMutex(pictq_mutex.get());
    pictq_size--;
    SDL_CondSignal(pictq_cond.get());
    SDL_UnlockMutex(pictq_mutex.get());
    return &pictq[pictq_rindex];
}

/* Add or subtract samples to get a better sync, return new
 audio buffer size */
int Player::synchronize_audio(short *samples,
                                 int samples_size, double pts)
{
    int n = 2 * audio_ctx->channels;
    
    if (sync_video) {
        double ref_clock = get_master_clock();
        double diff = get_audio_clock() - ref_clock;
        
        if (diff < AV_NOSYNC_THRESHOLD) {
            // accumulate the diffs
            audio_diff_cum = diff + audio_diff_avg_coef
            * audio_diff_cum;
            if (audio_diff_avg_count < AUDIO_DIFF_AVG_NB) {
                audio_diff_avg_count++;
            }
            else {
                double avg_diff = audio_diff_cum * (1.0 - audio_diff_avg_coef);
                if (fabs(avg_diff) >= audio_diff_threshold) {
                    int wanted_size = samples_size + ((int)(diff * audio_ctx->sample_rate) * n);
                    int min_size = samples_size * ((100 - SAMPLE_CORRECTION_PERCENT_MAX) / 100);
                    int max_size = samples_size * ((100 + SAMPLE_CORRECTION_PERCENT_MAX) / 100);
                    if (wanted_size < min_size) {
                        wanted_size = min_size;
                    }
                    else if (wanted_size > max_size) {
                        wanted_size = max_size;
                    }
                    if (wanted_size < samples_size) {
                        /* remove samples */
                        samples_size = wanted_size;
                    }
                    else if (wanted_size > samples_size) {
                        uint8_t *samples_end, *q;
                        int nb;
                        
                        /* add samples by copying final sample*/
                        nb = (samples_size - wanted_size);
                        samples_end = (uint8_t *)samples + samples_size - n;
                        q = samples_end + n;
                        while (nb > 0) {
                            memcpy(q, samples_end, n);
                            q += n;
                            nb -= n;
                        }
                        samples_size = wanted_size;
                    }
                }
            }
        }
        else {
            /* difference is TOO big; reset diff stuff */
            audio_diff_avg_count = 0;
            audio_diff_cum = 0;
        }
    }
    return samples_size;
}

double Player::synchronize_video(AVFrame *src_frame, double pts, double framerate)
{
    double frame_delay;
    
    if (pts != 0) {
        /* if we have pts, set video clock to it */
        video_clock = pts;
    }
    else {
        /* if we aren't given a pts, set it to the clock */
        pts = video_clock;
    }
    /* update the video clock */
    frame_delay = 1 / framerate;
    /* if we are repeating a frame, adjust clock accordingly */
    frame_delay += src_frame->repeat_pict * (frame_delay * 0.5);
    video_clock += frame_delay;
    return video_clock;
}


bool Player::configure_audio_filters()
{
    char asrc_args[256] = { 0 };
    std::shared_ptr<AVFilterGraph> graph(avfilter_graph_alloc(), [](AVFilterGraph *ptr) { avfilter_graph_free(&ptr); });
    AVFilterContext *filt_asrc = NULL, *filt_asink = NULL;
    AVFilterContext *filt_volume = NULL;
    AVFilterContext *filt_loudnorm = NULL;
    AVFilterContext *filt_aresample = NULL;
    
    afilt_in = NULL;
    afilt_out = NULL;
    agraph = NULL;
    
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
                                     asrc_args, NULL, graph.get()) < 0)
        return false;
    
    if (avfilter_graph_create_filter(&filt_asink,
                                     avfilter_get_by_name("abuffersink"), "ffplay_abuffersink",
                                     NULL, NULL, graph.get()) < 0)
        return false;
    
    if (audio_filter_src.audio_volume_dB != 0) {
        snprintf(asrc_args, sizeof(asrc_args),
                 "volume=%ddB", audio_filter_src.audio_volume_dB);
        if (avfilter_graph_create_filter(&filt_volume,
                                         avfilter_get_by_name("volume"), "ffplay_volume",
                                         asrc_args, NULL, graph.get()) < 0)
            return false;
    }
    if (audio_filter_src.audio_volume_auto) {
        snprintf(asrc_args, sizeof(asrc_args),
                 "f=500");
        if (avfilter_graph_create_filter(&filt_loudnorm,
                                         avfilter_get_by_name("dynaudnorm"), "ffplay_dynaudnorm",
                                         asrc_args, NULL, graph.get()) < 0)
            return false;
    }
    if (audio_filter_src.freq != audio_out_sample_rate) {
        snprintf(asrc_args, sizeof(asrc_args),
                 "%d", audio_out_sample_rate);
        if (avfilter_graph_create_filter(&filt_aresample,
                                         avfilter_get_by_name("aresample"), "ffplay_resample",
                                         asrc_args, NULL, graph.get()) < 0)
            return false;
    }
    
    AVFilterContext *filt_last = filt_asrc;
    if (filt_loudnorm) {
        if (avfilter_link(filt_last, 0, filt_loudnorm, 0) != 0)
            return false;
        filt_last = filt_loudnorm;
    }
    if (filt_volume) {
        if (avfilter_link(filt_last, 0, filt_volume, 0) != 0)
            return false;
        filt_last = filt_volume;
    }
    if (filt_aresample) {
        if (avfilter_link(filt_last, 0, filt_aresample, 0) != 0)
            return false;
        filt_last = filt_aresample;
    }
    if (avfilter_link(filt_last, 0, filt_asink, 0) != 0)
        return false;
    
    if (avfilter_graph_config(graph.get(), NULL) < 0)
        return false;
    
    afilt_in = filt_asrc;
    afilt_out = filt_asink;
    agraph = graph;
    return true;
}

bool Player::Configure_VideoFilter(AVFilterContext **filt_in, AVFilterContext **filt_out, AVFrame *frame, AVFilterGraph *graph)
{
    AVFilterContext *filt_deint = NULL;
    char args[256];
    
    snprintf(args, sizeof(args),
             "video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/%d",
             frame->width, frame->height, frame->format,
             video_st->time_base.num, video_st->time_base.den,
             video_st->codecpar->sample_aspect_ratio.num, FFMAX(video_st->codecpar->sample_aspect_ratio.den, 1));
    AVRational fr = av_guess_frame_rate(pFormatCtx, video_st, NULL);
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
    if (deinterlace) {
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
        if (avfilter_link(filt_deint, 0, *filt_out, 0) != 0)
            return false;
        if (avfilter_link(*filt_in, 0, filt_deint, 0) != 0)
            return false;
    }
    else {
        if (avfilter_link(*filt_in, 0, *filt_out, 0) != 0)
            return false;
    }
    return (avfilter_graph_config(graph, NULL) >= 0);
}




double Player::get_audio_clock()
{
    double pts;
    int hw_buf_size, bytes_per_sec, n;
    
    pts = audio_clock; /* maintained in the audio thread */
    hw_buf_size = audio_buf_size - audio_buf_index;
    bytes_per_sec = 0;
    n = audio_out_channels * 2;
    if (audio_st) {
        bytes_per_sec = audio_out_sample_rate * n;
    }
    if (bytes_per_sec) {
        pts -= (double)hw_buf_size / bytes_per_sec;
    }
    return pts;
}

double Player::get_video_clock()
{
    double delta;
    
    delta = (av_gettime() - video_current_pts_time) / 1000000.0;
    return video_current_pts + delta;
}

double Player::get_master_clock()
{
    if (sync_video) {
        return get_video_clock();
    }
    else {
        return get_audio_clock();
    }
}

void Player::schedule_refresh(int delay)
{
    remove_refresh++;
    SDL_AddTimer(delay, sdl_refresh_timer_cb, this);
}

void Player::Redraw()
{
    force_draw = true;
    video_refresh_timer();
}

int Player::stream_component_open(int stream_index)
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
    
    SDL_AudioSpec wanted_spec, spec;
    
    if (codecCtx->codec_type == AVMEDIA_TYPE_AUDIO) {
        wanted_spec.freq = codecCtx->sample_rate;
        wanted_spec.format = AUDIO_S16SYS;
        wanted_spec.channels = codecCtx->channels;
        wanted_spec.silence = 0;
        wanted_spec.samples = SDL_AUDIO_BUFFER_SIZE;
        wanted_spec.callback = audio_callback;
        wanted_spec.userdata = this;
        
        if ((audio_deviceID = SDL_OpenAudioDevice(
                                                  NULL,
                                                  0,
                                                  &wanted_spec,
                                                  &spec,
                                                  SDL_AUDIO_ALLOW_FREQUENCY_CHANGE | SDL_AUDIO_ALLOW_CHANNELS_CHANGE
                                                  )) == 0) {
            av_log(NULL, AV_LOG_PANIC, "SDL_OpenAudioDevice: %s\n", SDL_GetError());
            av_log(NULL, AV_LOG_PANIC, "want freq %d channels %d\n", wanted_spec.freq, wanted_spec.channels);
            
            wanted_spec.channels = 2;
            if ((audio_deviceID = SDL_OpenAudioDevice(
                                                      NULL,
                                                      0,
                                                      &wanted_spec,
                                                      &spec,
                                                      SDL_AUDIO_ALLOW_FREQUENCY_CHANGE | SDL_AUDIO_ALLOW_CHANNELS_CHANGE
                                                      )) == 0) {
                av_log(NULL, AV_LOG_PANIC, "SDL_OpenAudioDevice: %s\n", SDL_GetError());
                av_log(NULL, AV_LOG_PANIC, "want freq %d channels %d\n", wanted_spec.freq, wanted_spec.channels);
                
                return -1;
            }
        }
    }
    
    AVDictionary *opts = NULL;
    av_dict_set(&opts, "threads", "auto", 0);
    
    if (avcodec_open2(codecCtx.get(), codec, &opts) < 0) {
        av_log(NULL, AV_LOG_PANIC, "Unsupported codec!\n");
        return -1;
    }
    av_dict_free(&opts);
    
    pFormatCtx->streams[stream_index]->discard = AVDISCARD_DEFAULT;
    switch (codecCtx->codec_type) {
        case AVMEDIA_TYPE_AUDIO:
            audioStream = stream_index;
            audio_st = pFormatCtx->streams[stream_index];
            audio_ctx = codecCtx;
            audio_buf_size = 0;
            audio_buf_index = 0;
            audio_clock_start = NAN;
            audio_clock = NAN;
            
            audio_out_sample_rate = spec.freq;
            audio_out_channels = spec.channels;
            
            audio_callback_time = (double)av_gettime() / 1000000.0;
            audio_eof = audio_eof_enum::playing;
            break;
        case AVMEDIA_TYPE_VIDEO:
            videoStream = stream_index;
            video_st = pFormatCtx->streams[stream_index];
            video_ctx = codecCtx;
            video_clock_start = NAN;
            
            frame_timer = NAN;
            frame_last_delay = 10e-3;
            video_current_pts_time = av_gettime();
            
        {
            video_SAR = video_ctx->sample_aspect_ratio;
            double aspect_ratio = 0;
            if (video_ctx->sample_aspect_ratio.num == 0) {
                aspect_ratio = 0;
            }
            else {
                aspect_ratio = av_q2d(video_ctx->sample_aspect_ratio) *
                video_ctx->width / video_ctx->height;
            }
            if (aspect_ratio <= 0.0) {
                aspect_ratio = (double)video_ctx->width /
                (double)video_ctx->height;
            }
            video_height = codecCtx->height;
            video_width = ((int)rint(video_height * aspect_ratio)) & ~1;
            
            SDL_LockMutex(screen_mutex.get());
            subtitle.reset(NULL);
            texture = std::shared_ptr<SDL_Texture>(
                                                   SDL_CreateTexture(
                                                                     renderer,
                                                                     SDL_PIXELFORMAT_YV12,
                                                                     SDL_TEXTUREACCESS_STREAMING,
                                                                     video_width,
                                                                     video_height),
                                                   &SDL_DestroyTexture);
            subtitlelen = 0;
            subserial = 0;
            SDL_UnlockMutex(screen_mutex.get());
            
            // initialize SWS context for software scaling
            sws_ctx = std::shared_ptr<SwsContext>(
                                                  sws_getCachedContext(NULL,
                                                                       codecCtx->width, codecCtx->height,
                                                                       codecCtx->pix_fmt, video_width,
                                                                       video_height, AV_PIX_FMT_YUV420P,
                                                                       SWS_BICUBLIN, NULL, NULL, NULL
                                                                       ), &sws_freeContext);
            video_srcheight = codecCtx->height;
            video_srcwidth = codecCtx->width;
        }
            video_eof = false;
            video_tid = SDL_CreateThread(video_thread, "video", this);
            break;
        case AVMEDIA_TYPE_SUBTITLE:
            subtitleStream = stream_index;
            subtitle_st = pFormatCtx->streams[stream_index];
            subtitle_ctx = codecCtx;
            subtitle_tid = SDL_CreateThread(subtitle_thread, "subtitle", this);
            break;
        default:
            pFormatCtx->streams[stream_index]->discard = AVDISCARD_ALL;
            break;
    }
    return 0;
}

void Player::stream_component_close(int stream_index)
{
    AVFormatContext *ic = pFormatCtx;
    
    if (stream_index < 0 || (unsigned int)stream_index >= ic->nb_streams)
        return;
    
    AVCodecParameters *codecpar = ic->streams[stream_index]->codecpar;
    
    switch (codecpar->codec_type) {
        case AVMEDIA_TYPE_AUDIO:
            if (audio_deviceID > 0)
                SDL_CloseAudioDevice(audio_deviceID);
            audio_deviceID = 0;
            audioq.AbortQueue();
            break;
        case AVMEDIA_TYPE_VIDEO:
            videoq.AbortQueue();
            destory_pictures();
            if (video_tid) {
                SDL_WaitThread(video_tid, NULL);
                video_tid = 0;
            }
            destory_pictures();
            break;
        case AVMEDIA_TYPE_SUBTITLE:
            subtitleq.AbortQueue();
            subpictq.clear();
            if (subtitle_tid) {
                SDL_WaitThread(subtitle_tid, NULL);
                subtitle_tid = 0;
            }
            break;
        default:
            break;
    }
    
    ic->streams[stream_index]->discard = AVDISCARD_ALL;
    switch (codecpar->codec_type) {
        case AVMEDIA_TYPE_AUDIO:
            audio_st = NULL;
            audioStream = -1;
            break;
        case AVMEDIA_TYPE_VIDEO:
            video_st = NULL;
            videoStream = -1;
            break;
        case AVMEDIA_TYPE_SUBTITLE:
            subtitle_st = NULL;
            subtitleStream = -1;
            break;
        default:
            break;
    }
}

void Player::stream_cycle_channel(int codec_type)
{
    int start_index, old_index;
    int nb_streams = pFormatCtx->nb_streams;
    AVProgram *p = NULL;
    
    if (codec_type == AVMEDIA_TYPE_VIDEO) {
        start_index = old_index = videoStream;
    }
    else if (codec_type == AVMEDIA_TYPE_AUDIO) {
        start_index = old_index = audioStream;
    }
    else if (codec_type == AVMEDIA_TYPE_SUBTITLE) {
        start_index = old_index = subtitleStream;
    }
    else {
        return;
    }
    
    int stream_index = start_index;
    
    if (codec_type != AVMEDIA_TYPE_VIDEO && videoStream != -1) {
        p = av_find_program_from_stream(pFormatCtx, NULL, videoStream);
        if (p) {
            nb_streams = p->nb_stream_indexes;
            for (start_index = 0; start_index < nb_streams; start_index++)
                if (p->stream_index[start_index] == stream_index)
                    break;
            if (start_index == nb_streams)
                start_index = -1;
            stream_index = start_index;
        }
    }
    
    while (true) {
        if (++stream_index >= nb_streams)
        {
            if (codec_type == AVMEDIA_TYPE_SUBTITLE) {
                stream_index = -1;
                goto found;
            }
            if (start_index == -1)
            {
                if (p) p = NULL;
                else
                    break;
            }
            stream_index = 0;
        }
        if (stream_index == start_index)
        {
            if (p) p = NULL;
            else
                break;
        }
        auto st = pFormatCtx->streams[p ? p->stream_index[stream_index] : stream_index];
        if (st->codecpar->codec_type == codec_type) {
            /* check that parameters are OK */
            switch (codec_type) {
                case AVMEDIA_TYPE_AUDIO:
                    if (st->codecpar->sample_rate != 0 &&
                        st->codecpar->channels != 0)
                        goto found;
                    break;
                case AVMEDIA_TYPE_VIDEO:
                case AVMEDIA_TYPE_SUBTITLE:
                    goto found;
                default:
                    break;
            }
        }
    }
    return;
found:
    if (p && stream_index != -1)
        stream_index = p->stream_index[stream_index];
    
    if (old_index == stream_index) return;
    
    av_log(NULL, AV_LOG_INFO, "Stream Change %d -> %d\n", old_index, stream_index);
    
    if (codec_type == AVMEDIA_TYPE_VIDEO) {
        videoStream = -1;
    }
    else if (codec_type == AVMEDIA_TYPE_AUDIO) {
        audioStream = -1;
    }
    else if (codec_type == AVMEDIA_TYPE_SUBTITLE) {
        subtitleStream = -1;
    }
    else {
        return;
    }
    stream_component_close(old_index);
    if(stream_index >= 0)
        stream_component_open(stream_index);
    if (codec_type == AVMEDIA_TYPE_VIDEO) {
        videoStream = stream_index;
    }
    else if (codec_type == AVMEDIA_TYPE_AUDIO) {
        audioStream = stream_index;
    }
    else if (codec_type == AVMEDIA_TYPE_SUBTITLE) {
        subtitleStream = stream_index;
    }
    else {
        return;
    }
    
    // fix others
    if (codec_type == AVMEDIA_TYPE_VIDEO && videoStream != -1) {
        stream_cycle_channel(AVMEDIA_TYPE_AUDIO);
        stream_cycle_channel(AVMEDIA_TYPE_SUBTITLE);
    }
    char strbuf[64];
    sprintf(strbuf, "Stream Change %d -> %d", old_index, stream_index);
    if(overlay_text == "") {
        SDL_AddTimer(1000, timerdisplay_cb, this);
    }
    overlay_text = strbuf;
    Redraw();
    overlay_remove_time = av_gettime() + 3 * 1000 * 1000;
    
    stream_seek((int64_t)((get_master_clock() - 0.5) * AV_TIME_BASE), 0);
}

void Player::stream_seek(int64_t pos, int rel)
{
    if (!seek_req) {
        seek_pos = pos;
        seek_flags = 0;
        seek_rel = rel;
        seek_req = 1;
    }
    else {
        seek_pos_backorder = pos;
        seek_flags_backorder = 0;
        seek_rel_backorder = rel;
        seek_req_backorder = 1;
    }
    schedule_refresh(1);
}

void Player::stream_seek(double ratio)
{
    if (!seek_req) {
        seek_ratio = ratio;
        seek_req = 1;
    }
    else {
        seek_pos_backorder = ratio;
        seek_req_backorder = 1;
    }
    schedule_refresh(1);
}

void Player::EventOnSeek(double value, bool frac, bool pre)
{
    double pos = get_master_clock();
    
    if (isnan(pos))
        pos = prev_pos;
    else
        prev_pos = pos;
    
    int tns, thh, tmm, tss;
    int ns, hh, mm, ss;
    tns = 1;
    pos_ratio = get_duration();
    tns = (int)(pos_ratio);
    thh = tns / 3600;
    tmm = (tns % 3600) / 60;
    tss = (tns % 60);
    if (frac) {
        ns = (int)(value * tns);
    }
    else {
        pos += value;
        int64_t tmpns = (int64_t)pos;
        
        if (!isnan(video_clock_start))
            tmpns -= video_clock_start;
        else if (!isnan(audio_clock_start))
            tmpns -= audio_clock_start;

        ns = (int)(tmpns);
    }
    pos_ratio = ns / pos_ratio;
    hh = ns / 3600;
    mm = (ns % 3600) / 60;
    ss = (ns % 60);
    char strbuf[1024];
    if (frac) {
        sprintf(strbuf, "(%2.0f%%) %2d:%02d:%02d/%2d:%02d:%02d", value * 100,
                  hh, mm, ss, thh, tmm, tss);
    }
    else {
        sprintf(strbuf, "(%+.0f sec) %2d:%02d:%02d/%2d:%02d:%02d", value,
                  hh, mm, ss, thh, tmm, tss);
    }
    if(overlay_text == "") {
        SDL_AddTimer(1000, timerdisplay_cb, this);
    }
    overlay_text = strbuf;
    overlay_remove_time = av_gettime() + 2 * 1000 * 1000;
    Redraw();
    if (pre) {
        if (frac) {
            av_log(NULL, AV_LOG_INFO, "Seek to %2.0f%% (%2d:%02d:%02d) of total duration(%2d:%02d:%02d)\n", value * 100,
                   hh, mm, ss, thh, tmm, tss);
            int64_t ts = (int64_t)(value * pFormatCtx->duration);

            if (start_time_org != AV_NOPTS_VALUE){
                if (pts_rollover) {
                    ts += start_time_org;
                    ts += ((int64_t)1 << 33) / 90000.0 * AV_TIME_BASE;
                }
                else {
                    ts += start_time_org;
                }
            }
            if (pts_rollover)
                stream_seek(value);
            else
                stream_seek(ts, 0);
        }
        else {
            av_log(NULL, AV_LOG_INFO, "Seek to %.2f (%.2f)\n", pos, value);
            if (pts_rollover) {
                double ratio = pos;
                if (!isnan(video_clock_start))
                    ratio -= video_clock_start;
                else if (!isnan(audio_clock_start))
                    ratio -= audio_clock_start;
                ratio /= get_duration();
                av_log(NULL, AV_LOG_INFO, "ratio %.2f\n", ratio);
                stream_seek(ratio);
            }
            else {
                stream_seek((int64_t)(pos * AV_TIME_BASE), (int)(value));
            }
        }
    }
}

void Player::TogglePause()
{
    pause = !pause;
    if (pause) {
        if (audio_deviceID != 0)
            SDL_PauseAudioDevice(audio_deviceID, 1);
        change_pause = true;
    }
    else {
        frame_timer = NAN;
        schedule_refresh(1);
        if (audio_deviceID != 0)
            SDL_PauseAudioDevice(audio_deviceID, 0);
        change_pause = true;
    }
}

double Player::get_duration()
{
    if(!pFormatCtx){
        return 0;
    }
    if (pFormatCtx->duration) {
        return pFormatCtx->duration / 1000000.0;
    }
    else if (videoStream >= 0 && pFormatCtx->streams[videoStream]->duration) {
        return pFormatCtx->streams[videoStream]->duration / 1000000.0;
    }
    else if (audioStream >= 0 && pFormatCtx->streams[audioStream]->duration) {
        return pFormatCtx->streams[audioStream]->duration / 1000000.0;
    }
    else {
        return 0;
    }
}
void Player::set_clockduration(double pts)
{
    duration = get_duration();
    double t = pts;
    if (start_time_org != AV_NOPTS_VALUE){
        if (pts - start_time_org / 1000000.0 >((int64_t)1 << 32) / 90000.0) {
            t -= ((int64_t)1 << 33) / 90000.0;
            pts_rollover = true;
        }
        t -= start_time_org / 1000000.0;
    }
    else if (!isnan(video_clock_start))
        t -= video_clock_start / 1000000.0;
    else
        t -= audio_clock_start / 1000000.0;
    playtime = t;
}

void Player::destory_pictures()
{
    SDL_LockMutex(pictq_mutex.get());
    for (VideoPicture *p = pictq; p < &pictq[VIDEO_PICTURE_QUEUE_SIZE]; p++) {
        if (p == &pictq[pictq_windex]) continue;
        p->Free();
        p->pts = 0;
    }
    pictq_size = 1;
    SDL_CondSignal(pictq_cond.get());
    SDL_UnlockMutex(pictq_mutex.get());
}

void Player::destory_all_pictures()
{
    SDL_LockMutex(pictq_mutex.get());
    for (VideoPicture *p = pictq; p < &pictq[VIDEO_PICTURE_QUEUE_SIZE]; p++) {
        p->Free();
        p->pts = 0;
    }
    pictq_size = 0;
    SDL_CondSignal(pictq_cond.get());
    SDL_UnlockMutex(pictq_mutex.get());
}

void Player::Quit()
{
    quit = true;
    
    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = messageBase;
    event.user.data1 = this;
    SDL_PushEvent(&event);
}

bool Player::IsQuit()
{
    return quit || (audio_eof == audio_eof_enum::eof && video_eof);
}

void Player::Finalize()
{
    Quit();
    
    if (audio_deviceID > 0) {
        SDL_PauseAudioDevice(audio_deviceID, 0);
    }
    // avtivate threads for exit
    if (audioStream >= 0) {
        audioq.AbortQueue();
    }
    if (videoStream >= 0) {
        videoq.AbortQueue();
    }
    if (subtitleStream >= 0) {
        subtitleq.AbortQueue();
    }
    SDL_CondSignal(pictq_cond.get());
    struct stream_param *p = (struct stream_param *)param;
    if(p) {
        p->cancel(p->stream);
    }
    // wait for exit threads
    if (parse_tid)
        SDL_WaitThread(parse_tid, NULL);
    
    if (video_tid)
        SDL_WaitThread(video_tid, NULL);
    
    if (subtitle_tid)
        SDL_WaitThread(subtitle_tid, NULL);
    
    if (audio_deviceID > 0) {
        SDL_CloseAudioDevice(audio_deviceID);
        while(audio_callback_count >0)
            SDL_Delay(100);
    }
    
    destory_all_pictures();
    audioq.clear();
    videoq.clear();    
}

uint32_t sdl_refresh_timer_cb(uint32_t interval, void *opaque)
{
    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = messageBase + 2;
    event.user.data1 = opaque;
    SDL_PushEvent(&event);
    return 0; /* 0 means stop timer */
}

uint32_t timerdisplay_cb(uint32_t interval, void *param)
{
    Player *player = (Player *)param;
    if (player->overlay_remove_time < av_gettime()) {
        player->overlay_text = "";
        return 0;
    }
    return interval;
}

