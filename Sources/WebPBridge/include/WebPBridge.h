#ifndef WEBP_BRIDGE_H
#define WEBP_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
size_t fc_webp_encode(const uint8_t *rgba, int width, int height, int stride, float quality, uint8_t **output);
void fc_webp_free(void *output);
#endif
