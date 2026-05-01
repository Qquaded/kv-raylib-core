#include "raylib.h"
#include "rlgl.h"

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libavutil/imgutils.h>

// Load video from file
Video LoadVideo(const char *fileName)
{
    Video video = { 0 };
    video.streamIndex = -1;

    AVFormatContext *formatCtx = NULL;
    if (avformat_open_input(&formatCtx, fileName, NULL, NULL) != 0) {
        TraceLog(LOG_WARNING, "VIDEO: Failed to open video file");
        return video;
    }

    if (avformat_find_stream_info(formatCtx, NULL) < 0) {
        TraceLog(LOG_WARNING, "VIDEO: Failed to find stream info");
        avformat_close_input(&formatCtx);
        return video;
    }

    // Find the first video stream
    for (int i = 0; i < formatCtx->nb_streams; i++) {
        if (formatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            video.streamIndex = i;
            break;
        }
    }

    if (video.streamIndex == -1) {
        TraceLog(LOG_WARNING, "VIDEO: Didn't find a video stream");
        avformat_close_input(&formatCtx);
        return video;
    }

    AVCodecParameters *codecParameters = formatCtx->streams[video.streamIndex]->codecpar;
    const AVCodec *codec = avcodec_find_decoder(codecParameters->codec_id);
    if (!codec) {
        TraceLog(LOG_WARNING, "VIDEO: Unsupported codec");
        avformat_close_input(&formatCtx);
        return video;
    }

    AVCodecContext *codecCtx = avcodec_alloc_context3(codec);
    if (!codecCtx) {
        TraceLog(LOG_WARNING, "VIDEO: Failed to allocate codec context");
        avformat_close_input(&formatCtx);
        return video;
    }

    if (avcodec_parameters_to_context(codecCtx, codecParameters) < 0) {
        TraceLog(LOG_WARNING, "VIDEO: Failed to copy codec parameters to codec context");
        avcodec_free_context(&codecCtx);
        avformat_close_input(&formatCtx);
        return video;
    }

    if (avcodec_open2(codecCtx, codec, NULL) < 0) {
        TraceLog(LOG_WARNING, "VIDEO: Failed to open codec");
        avcodec_free_context(&codecCtx);
        avformat_close_input(&formatCtx);
        return video;
    }

    video.width = codecCtx->width;
    video.height = codecCtx->height;

    AVRational frameRate = formatCtx->streams[video.streamIndex]->avg_frame_rate;
    if (frameRate.den != 0 && frameRate.num != 0) {
        video.frameRate = av_q2d(frameRate);
    } else {
        video.frameRate = 30.0; // fallback
    }

    struct SwsContext *swsCtx = sws_getContext(
        codecCtx->width, codecCtx->height, codecCtx->pix_fmt,
        video.width, video.height, AV_PIX_FMT_RGBA,
        SWS_BILINEAR, NULL, NULL, NULL
    );

    Image img = { 0 };
    img.width = video.width;
    img.height = video.height;
    img.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;
    img.mipmaps = 1;
    img.data = MemAlloc(video.width * video.height * 4); // RGBA

    video.texture = LoadTextureFromImage(img);
    UnloadImage(img);

    video.ctx = formatCtx;
    video.vctx = codecCtx;
    video.frame = av_frame_alloc();
    video.sws = swsCtx;
    video.ready = true;
    video.playing = false;
    video.timeElapsed = 0.0;
    video.nextPts = -1;

    TraceLog(LOG_INFO, "VIDEO: [%s] Loaded successfully (%ix%i) at %.2f FPS", fileName, video.width, video.height, video.frameRate);

    return video;
}

// Unload video
void UnloadVideo(Video video)
{
    if (video.ctx) {
        avformat_close_input((AVFormatContext**)&video.ctx);
    }
    if (video.vctx) {
        avcodec_free_context((AVCodecContext**)&video.vctx);
    }
    if (video.frame) {
        av_frame_free((AVFrame**)&video.frame);
    }
    if (video.sws) {
        sws_freeContext((struct SwsContext *)video.sws);
    }
    UnloadTexture(video.texture);
}

// Start video playing
void PlayVideo(Video *video)
{
    if (video && video->ready) {
        video->playing = true;
    }
}

// Stop video playing
void StopVideo(Video *video)
{
    if (video && video->ready) {
        video->playing = false;
        // Optionally reset stream to beginning
        if (video->ctx) {
            AVFormatContext *formatCtx = (AVFormatContext *)video->ctx;
            av_seek_frame(formatCtx, video->streamIndex, 0, AVSEEK_FLAG_BACKWARD);
            avcodec_flush_buffers((AVCodecContext *)video->vctx);
            video->timeElapsed = 0.0;
            video->nextPts = -1;
        }
    }
}

// Update video frame to texture
void UpdateVideo(Video *video)
{
    if (!video || !video->ready || !video->playing) return;

    video->timeElapsed += GetFrameTime();

    AVFormatContext *formatCtx = (AVFormatContext *)video->ctx;
    AVCodecContext *codecCtx = (AVCodecContext *)video->vctx;
    AVFrame *frame = (AVFrame *)video->frame;
    struct SwsContext *swsCtx = (struct SwsContext *)video->sws;
    AVStream *stream = formatCtx->streams[video->streamIndex];

    // Check if it's time to decode the next frame
    double currentTime = video->timeElapsed;

    if (video->nextPts != -1) {
        double nextTime = video->nextPts * av_q2d(stream->time_base);
        if (currentTime < nextTime) {
            return; // Not time yet
        }
    }

    AVPacket *packet = av_packet_alloc();
    if (!packet) return;

    bool frameDecoded = false;

    while (av_read_frame(formatCtx, packet) >= 0) {
        if (packet->stream_index == video->streamIndex) {
            int response = avcodec_send_packet(codecCtx, packet);
            if (response < 0 && response != AVERROR(EAGAIN) && response != AVERROR_EOF) {
                TraceLog(LOG_WARNING, "VIDEO: Error while sending a packet to the decoder");
                break;
            }

            while (response >= 0) {
                response = avcodec_receive_frame(codecCtx, frame);
                if (response == AVERROR(EAGAIN) || response == AVERROR_EOF) {
                    break;
                } else if (response < 0) {
                    TraceLog(LOG_WARNING, "VIDEO: Error while receiving a frame from the decoder");
                    break;
                }

                if (swsCtx) {
                    uint8_t *destData[4] = { NULL };
                    int destLinesize[4] = { 0 };

                    av_image_alloc(destData, destLinesize, video->width, video->height, AV_PIX_FMT_RGBA, 1);

                    sws_scale(swsCtx, (const uint8_t * const *)frame->data, frame->linesize,
                              0, codecCtx->height, destData, destLinesize);

                    UpdateTexture(video->texture, destData[0]);

                    av_freep(&destData[0]);
                }

                if (frame->pts != AV_NOPTS_VALUE) {
                    video->nextPts = frame->pts;
                } else {
                    // Try to guess next pts based on framerate if not provided
                    video->nextPts += (int64_t)(1.0 / (video->frameRate * av_q2d(stream->time_base)));
                }

                frameDecoded = true;
                break; // Only decode one frame per UpdateVideo call
            }
        }
        av_packet_unref(packet);
        if (frameDecoded) break;
    }

    av_packet_free(&packet);

    // Check if video ended
    if (!frameDecoded) {
        StopVideo(video);
    }
}
