//
//  packetQueue.cpp
//  fftest
//
//  Created by rei8 on 2019/10/18.
//  Copyright © 2019 lithium03. All rights reserved.
//

#include "packetQueue.hpp"
#include "player_base.hpp"

#include <mutex>
#include <memory>

extern AVPacket flush_pkt;
extern AVPacket eof_pkt;
extern AVPacket abort_pkt;

PacketQueue::PacketQueue(Player *parent) : first_pkt(NULL), last_pkt(NULL)
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
    
    {
        std::lock_guard<std::mutex> lk(mutex);
        
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
    }
    cond.notify_one();

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
    
    {
        std::lock_guard<std::mutex> lk(mutex);
        
        if (!last_pkt)
            first_pkt = pkt1;
        else
            last_pkt->next = pkt1;
        last_pkt = pkt1;
        nb_packets++;
        size += pkt1->pkt.size;
    }
    cond.notify_one();

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
    
    {
        std::lock_guard<std::mutex> lk(mutex);
        
        if (!last_pkt)
            first_pkt = pkt1;
        else
            last_pkt->next = pkt1;
        last_pkt = pkt1;
        nb_packets++;
        size += pkt1->pkt.size;
    }
    cond.notify_one();

    return 0;
}

int PacketQueue::get(AVPacket *pkt, int block)
{
    AVPacketList *pkt1;
    int ret;
    
    std::unique_lock<std::mutex> lk(mutex);
    
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
            cond.wait(lk, [this] { return parent->IsQuit() || nb_packets > 0; });
        }
    }
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
    
    {
        std::lock_guard<std::mutex> lk(mutex);

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
    }
    cond.notify_one();

    return;
}

void PacketQueue::clear()
{
    AVPacketList *pkt1;
    
    std::lock_guard<std::mutex> lk(mutex);

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
}


//********************************************************

VideoPicture::~VideoPicture()
{
    this->Free();
}

bool VideoPicture::Allocate(int width, int height)
{
    Free();
    if (av_image_alloc(bmp.data, bmp.linesize, width, height, AV_PIX_FMT_RGBA, 1) < 0)
        return false;
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

//**************************************************************************

SubtitlePictureQueue::SubtitlePictureQueue(Player *parent)
{
    this->parent = parent;
}

SubtitlePictureQueue::~SubtitlePictureQueue()
{
    clear();
}

void SubtitlePictureQueue::clear()
{
    std::lock_guard<std::mutex> lk(mutex);
    while (!queue.empty())
        queue.pop();
}

void SubtitlePictureQueue::put(std::shared_ptr<SubtitlePicture> Pic)
{
    std::lock_guard<std::mutex> lk(mutex);
    queue.push(Pic);
    cond.notify_one();
}

int SubtitlePictureQueue::peek(std::shared_ptr<SubtitlePicture> &Pic)
{
    int ret;
    std::unique_lock<std::mutex> lk(mutex);
    while (true) {
        if (parent->IsQuit()) {
            ret = -1;
            break;
        }
        if (!queue.empty()) {
            Pic = queue.front();
            ret = 0;
            break;
        }
        else {
            ret = 1;
            break;
        }
        //cond.wait(lk, [this] { return parent->IsQuit() || !queue.empty(); });
    }
    return ret;
}

int SubtitlePictureQueue::get(std::shared_ptr<SubtitlePicture> &Pic)
{
    int ret;
    std::unique_lock<std::mutex> lk(mutex);
    while (true) {
        if (parent->IsQuit()) {
            ret = -1;
            break;
        }
        if (!queue.empty()) {
            Pic = queue.front();
            queue.pop();
            ret = 0;
            break;
        }
        else {
            ret = 1;
            break;
        }
        //cond.wait(lk, [this] { return parent->IsQuit() || !queue.empty(); });
    }
    return ret;
}
