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
public:
    AVPacketList *first_pkt = NULL, *last_pkt = NULL;
    int nb_packets = 0;
    int size = 0;
    
    PacketQueue(Converter *parent);
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
    Converter *parent = NULL;
    std::mutex mutex;
    std::condition_variable cond;
    std::queue<std::shared_ptr<SubtitlePicture>> queue;
public:
    SubtitlePictureQueue(Converter *parent);
    ~SubtitlePictureQueue();
    void clear();
    void put(std::shared_ptr<SubtitlePicture> Pic);
    int peek(std::shared_ptr<SubtitlePicture>& Pic);
    int get(std::shared_ptr<SubtitlePicture> &Pic);
};


#endif /* packetQueue_hpp */
