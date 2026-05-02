#ifndef UNORingBuffer_h
#define UNORingBuffer_h

#include <stdatomic.h>
#include <stdint.h>
#include <stdbool.h>

/// v7.1: Lock-Free Ring Buffer Header (C-Atomic)
/// Hardware-aligned for Apple Silicon memory consistency.
typedef struct {
    atomic_uint_fast32_t head;
    atomic_uint_fast32_t tail;
    uint32_t capacity;
    uint8_t data[]; // Flexible array member for raw buffer
} UNORingBufferHeader;

static inline void uno_ring_buffer_init(UNORingBufferHeader *header, uint32_t capacity) {
    atomic_init(&header->head, 0);
    atomic_init(&header->tail, 0);
    header->capacity = capacity;
}

static inline uint32_t uno_ring_buffer_get_head(UNORingBufferHeader *header) {
    return atomic_load_explicit(&header->head, memory_order_acquire);
}

static inline void uno_ring_buffer_set_head(UNORingBufferHeader *header, uint32_t val) {
    atomic_store_explicit(&header->head, val, memory_order_release);
}

static inline uint32_t uno_ring_buffer_get_tail(UNORingBufferHeader *header) {
    return atomic_load_explicit(&header->tail, memory_order_acquire);
}

static inline void uno_ring_buffer_set_tail(UNORingBufferHeader *header, uint32_t val) {
    atomic_store_explicit(&header->tail, val, memory_order_release);
}

#endif /* UNORingBuffer_h */
