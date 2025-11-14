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

PacketQueue::PacketQueue(Player *parent)
{
    this->parent = parent;
}

PacketQueue::~PacketQueue()
{
    clear();
}

void PacketQueue::AbortQueue()
{
    aborted = true;
    {
        std::lock_guard<std::mutex> lk(mutex);

        while(!queue.empty()) {
            auto pkt = queue.front();
            queue.pop_front();
            av_packet_unref(pkt);
            av_packet_free(&pkt);
        }

        queue.push_back(av_packet_clone(&abort_pkt));
        queue.shrink_to_fit();
    }
    cond.notify_one();

    return;
}

int PacketQueue::putEOF()
{
    {
        std::lock_guard<std::mutex> lk(mutex);

        queue.push_back(av_packet_clone(&eof_pkt));
    }
    cond.notify_one();

    return 0;
}

int PacketQueue::put(AVPacket *pkt)
{
    if(aborted) {
        return -1;
    }

    {
        std::lock_guard<std::mutex> lk(mutex);

        queue.push_back(av_packet_clone(pkt));
    }
    cond.notify_one();

    return 0;
}

int PacketQueue::get(AVPacket *pkt, int block)
{
    int ret;
    
    std::unique_lock<std::mutex> lk(mutex);
    
    for (;;) {
        
        if (parent->IsQuit()) {
            ret = -1;
            break;
        }
        
        if(!queue.empty()) {
            av_packet_move_ref(pkt, queue.front());
            av_packet_unref(queue.front());
            av_packet_free(&queue.front());
            queue.pop_front();
            ret = 1;
            break;
        }
        else if (!block) {
            ret = 0;
            break;
        }
        else {
            cond.wait(lk, [this] { return parent->IsQuit() || !queue.empty(); });
        }
    }
    queue.shrink_to_fit();
    return ret;
}

void PacketQueue::flush()
{
    {
        std::lock_guard<std::mutex> lk(mutex);

        while(!queue.empty()) {
            auto pkt = queue.front();
            queue.pop_front();
            av_packet_unref(pkt);
            av_packet_free(&pkt);
        }

        queue.push_back(av_packet_clone(&flush_pkt));
        queue.shrink_to_fit();
    }
    cond.notify_one();

    return;
}

void PacketQueue::clear()
{
    std::lock_guard<std::mutex> lk(mutex);

    while(!queue.empty()) {
        auto pkt = queue.front();
        queue.pop_front();
        av_packet_unref(pkt);
        av_packet_free(&pkt);
    }
    queue.shrink_to_fit();
    aborted = false;
}

size_t PacketQueue::size()
{
    return queue.size();
}

//********************************************************

VideoPicture::~VideoPicture()
{
    this->free();
}

bool VideoPicture::Allocate(int width, int height)
{
    free();
    if (av_image_alloc(bmp.data, bmp.linesize, width, height, AV_PIX_FMT_YUV420P, 16) < 0)
        return false;
    this->width = width;
    this->height = height;
    allocated = true;
    return true;
}

void VideoPicture::free()
{
    av_freep(&bmp.data[0]);
    av_frame_unref(&bmp);
    allocated = false;
    height = width = 0;
}

//**************************************************************************
SubtitlePicture::~SubtitlePicture()
{
    avsubtitle_free(&sub);
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
    queue.clear();
    queue.shrink_to_fit();
}

void SubtitlePictureQueue::put(std::shared_ptr<SubtitlePicture> Pic)
{
    std::lock_guard<std::mutex> lk(mutex);
    queue.push_back(std::move(Pic));
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

int SubtitlePictureQueue::peek2(std::shared_ptr<SubtitlePicture> &Pic)
{
    int ret;
    std::unique_lock<std::mutex> lk(mutex);
    while (true) {
        if (parent->IsQuit()) {
            ret = -1;
            break;
        }
        if (queue.size() > 1) {
            auto p1 = queue.front();
            queue.pop_front();
            Pic = queue.front();
            queue.push_front(p1);
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
            Pic = std::move(queue.front());
            queue.pop_front();
            ret = 0;
            break;
        }
        else {
            ret = 1;
            break;
        }
        //cond.wait(lk, [this] { return parent->IsQuit() || !queue.empty(); });
    }
    queue.shrink_to_fit();
    return ret;
}
