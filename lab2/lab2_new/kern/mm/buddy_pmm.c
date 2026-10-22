#include <buddy_pmm.h>
#include <list.h>
#include <stdio.h>

// lab2 任务三：伙伴系统核心实现；学号：2412891
typedef struct {
    list_entry_t free_list;
    size_t nr_free;
} buddy_area_t;

static buddy_area_t buddy_area[BUDDY_MAX_ORDER + 1];
static size_t buddy_total_free;

/* 阶为 k 的伙伴块恰好包含 2^k 个连续页面。 */
static size_t
order_pages(size_t order) {
    return ((size_t)1) << order;
}

static size_t
ceil_order(size_t n) {
    /* 非 2 的幂次请求向上取整，占用下一个更大的伙伴块。 */
    size_t order = 0;
    size_t pages = 1;
    while (pages < n && order < BUDDY_MAX_ORDER) {
        pages <<= 1;
        order++;
    }
    return order;
}

static void
buddy_reset(void) {
    for (size_t order = 0; order <= BUDDY_MAX_ORDER; order++) {
        list_init(&buddy_area[order].free_list);
        buddy_area[order].nr_free = 0;
    }
    buddy_total_free = 0;
}

static void
buddy_add_block(struct Page *base, size_t order) {
    /* 每个阶维护独立空闲链表，便于记录块的拆分和合并。 */
    base->property = order;
    SetPageProperty(base);
    list_add(&buddy_area[order].free_list, &base->page_link);
    buddy_area[order].nr_free++;
    buddy_total_free += order_pages(order);
}

static void
buddy_remove_block(struct Page *base, size_t order) {
    list_del(&base->page_link);
    buddy_area[order].nr_free--;
    buddy_total_free -= order_pages(order);
    ClearPageProperty(base);
}

static struct Page *
buddy_find_block(struct Page *base, size_t order) {
    list_entry_t *le = &buddy_area[order].free_list;
    while ((le = list_next(le)) != &buddy_area[order].free_list) {
        struct Page *p = le2page(le, page_link);
        if (p == base) {
            return p;
        }
    }
    return NULL;
}

static void
buddy_init(void) {
    buddy_reset();
}

static void
buddy_init_memmap(struct Page *base, size_t n) {
    assert(n > 0);
    buddy_reset();

    for (struct Page *p = base; p < base + n; p++) {
        assert(PageReserved(p));
        p->flags = 0;
        p->property = 0;
        set_page_ref(p, 0);
        list_init(&p->page_link);
    }

    /* 将任意长度的初始区域分解为按边界对齐的 2 的幂次块。 */
    size_t offset = 0;
    while (offset < n) {
        size_t order = 0;
        while (order < BUDDY_MAX_ORDER &&
               order_pages(order + 1) <= n - offset &&
               (offset % order_pages(order + 1)) == 0) {
            order++;
        }
        buddy_add_block(base + offset, order);
        offset += order_pages(order);
    }
}

static struct Page *
buddy_alloc_pages(size_t n) {
    assert(n > 0);
    size_t wanted = ceil_order(n);
    if (wanted == BUDDY_MAX_ORDER && n > order_pages(wanted)) {
        return NULL;
    }

    /* 从更高阶的非空链表取块，再逐级拆分到请求的阶。 */
    size_t order = wanted;
    while (order <= BUDDY_MAX_ORDER &&
           list_empty(&buddy_area[order].free_list)) {
        order++;
    }
    if (order > BUDDY_MAX_ORDER) {
        return NULL;
    }

    list_entry_t *le = list_next(&buddy_area[order].free_list);
    struct Page *block = le2page(le, page_link);
    buddy_remove_block(block, order);

    while (order > wanted) {
        order--;
        struct Page *right = block + order_pages(order);
        buddy_add_block(right, order);
    }

    for (struct Page *p = block; p < block + order_pages(wanted); p++) {
        p->flags = 0;
        p->property = 0;
        set_page_ref(p, 0);
    }
    return block;
}

static void
buddy_free_pages(struct Page *base, size_t n) {
    assert(n > 0);
    size_t order = ceil_order(n);
    size_t block_pages = order_pages(order);
    for (struct Page *p = base; p < base + block_pages; p++) {
        assert(!PageReserved(p));
        p->flags = 0;
        p->property = 0;
        set_page_ref(p, 0);
        list_init(&p->page_link);
    }

    /* 伙伴索引 = 当前块索引 XOR 当前块大小；相同阶的伙伴可以合并。 */
    while (order < BUDDY_MAX_ORDER) {
        size_t index = (size_t)(base - pages);
        size_t buddy_index = index ^ block_pages;
        struct Page *buddy = pages + buddy_index;
        if (buddy_find_block(buddy, order) == NULL) {
            break;
        }
        buddy_remove_block(buddy, order);
        if (buddy < base) {
            base = buddy;
        }
        order++;
        block_pages <<= 1;
    }
    buddy_add_block(base, order);
}

static size_t
buddy_nr_free_pages(void) {
    return buddy_total_free;
}

static void
buddy_check(void) {
    buddy_challenge_check();
}

const struct pmm_manager buddy_pmm_manager = {
    .name = "buddy_pmm_manager",
    .init = buddy_init,
    .init_memmap = buddy_init_memmap,
    .alloc_pages = buddy_alloc_pages,
    .free_pages = buddy_free_pages,
    .nr_free_pages = buddy_nr_free_pages,
    .check = buddy_check,
};

// lab2 任务三：伙伴系统测试；学号：2413740
void
buddy_challenge_check(void) {
    static struct Page test_pages[64];
    for (size_t i = 0; i < 64; i++) {
        test_pages[i].flags = 0;
        SetPageReserved(&test_pages[i]);
        list_init(&test_pages[i].page_link);
    }

    /* 合并逻辑使用全局 Page 数组计算块索引，因此测试前临时替换 pages。 */
    struct Page *saved_pages = pages;
    pages = test_pages;
    buddy_init_memmap(test_pages, 64);
    assert(buddy_nr_free_pages() == 64);

    struct Page *a = buddy_alloc_pages(3);
    struct Page *b = buddy_alloc_pages(8);
    assert(a != NULL && b != NULL && a != b);
    assert(buddy_nr_free_pages() == 52);
    buddy_free_pages(a, 3);
    buddy_free_pages(b, 8);

    struct Page *whole = buddy_alloc_pages(64);
    assert(whole == test_pages);
    assert(buddy_alloc_pages(1) == NULL);
    buddy_free_pages(whole, 64);
    assert(buddy_nr_free_pages() == 64);

    pages = saved_pages;
    cprintf("[Lab2] Buddy System: PASS\n");
}
