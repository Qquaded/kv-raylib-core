#include "raylib.h"
#include "rlgl.h"

#include <stdio.h>
#include <stddef.h>

#define PL_MPEG_IMPLEMENTATION
#include "pl_mpeg.h"

// Load video from file
Video LoadVideo(const char *fileName)
{
    Video video = { 0 };

    plm_t *plm = plm_create_with_filename(fileName);
    if (!plm) {
        TraceLog(LOG_WARNING, "VIDEO: [%s] Failed to open video file", fileName);
        return video;
    }

    video.width = plm_get_width(plm);
    video.height = plm_get_height(plm);
    video.frameRate = plm_get_framerate(plm);

    Image img = { 0 };
    img.width = video.width;
    img.height = video.height;
    img.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;
    img.mipmaps = 1;
    img.data = MemAlloc(video.width * video.height * 4); // RGBA

    video.texture = LoadTextureFromImage(img);
    UnloadImage(img);

    video.ctx = plm;
    video.ready = true;
    video.playing = false;

    TraceLog(LOG_INFO, "VIDEO: [%s] Loaded successfully (%ix%i) at %.2f FPS", fileName, video.width, video.height, video.frameRate);

    return video;
}

// Unload video
void UnloadVideo(Video video)
{
    if (video.ctx) {
        plm_destroy((plm_t *)video.ctx);
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
        if (video->ctx) {
            plm_rewind((plm_t *)video->ctx);
        }
    }
}

// Update video frame to texture
void UpdateVideo(Video *video)
{
    if (!video || !video->ready || !video->playing || !video->ctx) return;

    plm_t *plm = (plm_t *)video->ctx;

    // Decode next frame if time has elapsed
    plm_frame_t *frame = plm_decode_video(plm);

    if (frame) {
        // Convert to RGBA
        uint8_t *dest = MemAlloc(video->width * video->height * 4);
        if (dest) {
            plm_frame_to_rgba(frame, dest, video->width * 4);
            UpdateTexture(video->texture, dest);
            MemFree(dest);
        }
    }

    if (plm_has_ended(plm)) {
        StopVideo(video);
    }
}
