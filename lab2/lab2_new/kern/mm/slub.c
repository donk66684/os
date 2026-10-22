#include <slub.h>
#include <stdio.h>
#include <string.h>

#define SLUB_MAX_SLABS 32
#define SLUB_MAX_OBJECTS 512
#define SLUB_MAX_LARGE 16

typedef struct {
    struct Page *page;
    size_t object_size;
    size_t stride;
    size_t capacity;
    size_t inuse;
    uint8_t used[SLUB_MAX_OBJECTS];
} slub_slab_t;

typedef struct {
    void *address;
    struct Page *pages;
    size_t page_count;
} slub_large_t;

/* 使用静态元数据，使分配器在通用堆尚未建立时也可以工作。 */
static slub_slab_t slabs[SLUB_MAX_SLABS];
static slub_large_t large_allocs[SLUB_MAX_LARGE];

static uintptr_t
page_address(struct Page *page) {
    /* 将 PMM 返回的物理页框转换为内核虚拟地址。 */
    return page2pa(page) + va_pa_offset;
}

void
slub_init(void) {
    memset(slabs, 0, sizeof(slabs));
    memset(large_allocs, 0, sizeof(large_allocs));
}

static slub_slab_t *
new_slab(size_t size) {
    struct Page *page = alloc_page();
    if (page == NULL) {
        return NULL;
    }

    for (size_t i = 0; i < SLUB_MAX_SLABS; i++) {
        if (slabs[i].page == NULL) {
            slub_slab_t *slab = &slabs[i];
            slab->page = page;
            slab->object_size = size;
            /* 小对象仍按指针大小对齐，保证访问安全。 */
            slab->stride = size < sizeof(uintptr_t) ? sizeof(uintptr_t) : size;
            slab->capacity = PGSIZE / slab->stride;
            if (slab->capacity > SLUB_MAX_OBJECTS) {
                slab->capacity = SLUB_MAX_OBJECTS;
            }
            slab->inuse = 0;
            memset(slab->used, 0, sizeof(slab->used));
            return slab;
        }
    }

    free_page(page);
    return NULL;
}

void *
slub_alloc(size_t size) {
    if (size == 0) {
        return NULL;
    }

    /* 大对象不使用单页 slab，而是直接分配连续物理页。 */
    if (size > PGSIZE) {
        size_t page_count = (size + PGSIZE - 1) / PGSIZE;
        struct Page *page = alloc_pages(page_count);
        if (page == NULL) {
            return NULL;
        }
        for (size_t i = 0; i < SLUB_MAX_LARGE; i++) {
            if (large_allocs[i].address == NULL) {
                large_allocs[i].pages = page;
                large_allocs[i].page_count = page_count;
                large_allocs[i].address = (void *)page_address(page);
                return large_allocs[i].address;
            }
        }
        free_pages(page, page_count);
        return NULL;
    }

    /* 优先复用相同对象大小的已有 slab，只有不足时才申请新页。 */
    for (size_t i = 0; i < SLUB_MAX_SLABS; i++) {
        slub_slab_t *slab = &slabs[i];
        if (slab->page != NULL && slab->object_size == size &&
            slab->inuse < slab->capacity) {
            for (size_t j = 0; j < slab->capacity; j++) {
                if (!slab->used[j]) {
                    slab->used[j] = 1;
                    slab->inuse++;
                    return (void *)(page_address(slab->page) + j * slab->stride);
                }
            }
        }
    }

    slub_slab_t *slab = new_slab(size);
    if (slab == NULL || slab->capacity == 0) {
        return NULL;
    }
    slab->used[0] = 1;
    slab->inuse = 1;
    return (void *)page_address(slab->page);
}

void
slub_free(void *ptr) {
    if (ptr == NULL) {
        return;
    }

    /* 大对象通过精确的起始地址进行识别。 */
    for (size_t i = 0; i < SLUB_MAX_LARGE; i++) {
        if (large_allocs[i].address == ptr) {
            free_pages(large_allocs[i].pages, large_allocs[i].page_count);
            large_allocs[i].address = NULL;
            large_allocs[i].pages = NULL;
            large_allocs[i].page_count = 0;
            return;
        }
    }

    /* 对 slab 对象检查地址范围和步长，从而恢复位图索引。 */
    for (size_t i = 0; i < SLUB_MAX_SLABS; i++) {
        slub_slab_t *slab = &slabs[i];
        if (slab->page == NULL) {
            continue;
        }
        uintptr_t start = page_address(slab->page);
        uintptr_t end = start + slab->stride * slab->capacity;
        uintptr_t address = (uintptr_t)ptr;
        if (address >= start && address < end &&
            (address - start) % slab->stride == 0) {
            size_t index = (address - start) / slab->stride;
            assert(index < slab->capacity && slab->used[index]);
            slab->used[index] = 0;
            slab->inuse--;
            if (slab->inuse == 0) {
                free_page(slab->page);
                memset(slab, 0, sizeof(*slab));
            }
            return;
        }
    }

    panic("slub_free: invalid pointer");
}

void
slub_challenge_check(void) {
    size_t before = nr_free_pages();
    slub_init();

    void *small = slub_alloc(1);
    void *medium = slub_alloc(24);
    void *large = slub_alloc(1000);
    void *multi_page = slub_alloc(PGSIZE + 37);
    assert(small != NULL && medium != NULL && large != NULL && multi_page != NULL);

    ((uint8_t *)small)[0] = 0x11;
    ((uint8_t *)medium)[23] = 0x22;
    ((uint8_t *)large)[999] = 0x33;
    ((uint8_t *)multi_page)[PGSIZE + 36] = 0x44;
    assert(((uint8_t *)small)[0] == 0x11);
    assert(((uint8_t *)medium)[23] == 0x22);
    assert(((uint8_t *)large)[999] == 0x33);
    assert(((uint8_t *)multi_page)[PGSIZE + 36] == 0x44);

    slub_free(small);
    slub_free(medium);
    slub_free(large);
    slub_free(multi_page);
    assert(nr_free_pages() == before);
    cprintf("[Challenge] SLUB: PASS\n");
}
