//
//  packetQueue.hpp
//  ffconverter
//
//  Created by rei8 on 2019/11/13.
//  Copyright © 2019 lithium03. All rights reserved.
//

#ifndef packetQueue_hpp
#define packetQueue_hpp

#include <mutex>
#include <queue>
#include <condition_variable>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
}

class Converter;

class PacketQueue
{
private:
    Converter *parent = NULL;
    std::mutex mutex;
    std::condition_variable cond;
    bool aborted = false;
public:
    std::deque<AVPacket*> queue;
    
    PacketQueue(Converter *parent);
    ~PacketQueue();
    void AbortQueue();
    int putEOF();
    int put(AVPacket *pkt);
    int get(AVPacket *pkt, int block);
    void flush();
    void clear();
    size_t size();
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
    void free();
};

class SubtitlePicture
{
public:
    AVSubtitle sub;
    int subw;
    int subh;
    double pts;
    int64_t serial;
    
    ~SubtitlePicture();
};

class SubtitlePictureQueue
{
private:
    Converter *parent = NULL;
    std::mutex mutex;
    std::condition_variable cond;
    std::deque<std::shared_ptr<SubtitlePicture>> queue;
public:
    SubtitlePictureQueue(Converter *parent);
    ~SubtitlePictureQueue();
    void clear();
    void put(std::shared_ptr<SubtitlePicture> Pic);
    int peek(std::shared_ptr<SubtitlePicture>& Pic);
    int peek2(std::shared_ptr<SubtitlePicture>& Pic);
    int get(std::shared_ptr<SubtitlePicture> &Pic);
};


#endif /* packetQueue_hpp */
