#include "WebPBridge.h"
#include "src/webp/encode.h"
size_t fc_webp_encode(const uint8_t *rgba, int width, int height, int stride, float quality, uint8_t **output) {
    return WebPEncodeRGBA(rgba, width, height, stride, quality, output);
}
void fc_webp_free(void *output) { WebPFree(output); }
