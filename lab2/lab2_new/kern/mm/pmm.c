#include <default_pmm.h>
#include <best_fit_pmm.h>
#include <buddy_pmm.h>
#include <defs.h>
#include <error.h>
#include <memlayout.h>
#include <mmu.h>
#include <pmm.h>
#include <sbi.h>
#include <stdio.h>
#include <string.h>
#include <riscv.h>
#include <dtb.h>
#include <slub.h>

// 物理页描述符数组的虚拟地址
struct Page *pages;
// 物理内存总页数
size_t npage = 0;
// 内核镜像映射到虚拟地址 KERNBASE，对应设备树报告的物理起始地址
uint64_t va_pa_offset;
// RISC-V 的 DRAM 从 0x80000000 开始
// DRAM_BASE 在 riscv.h 中定义为 0x80000000
const size_t nbase = DRAM_BASE / PGSIZE;

// 启动阶段页表的虚拟地址
uintptr_t *satp_virtual = NULL;
// 启动阶段页表的物理地址
uintptr_t satp_physical;

// 物理内存管理器
const struct pmm_manager *pmm_manager;


static void check_alloc_page(void);

// 初始化一个 pmm_manager 实例
static void init_pmm_manager(void) {
    /*
     * pmm_manager is the common interface for all page allocators.  The
     * required Lab2 path keeps Best-Fit as the active allocator; Buddy and
     * SLUB are checked independently below so their tests do not alter the
     * normal kernel allocation policy.
     */
    pmm_manager = &best_fit_pmm_manager;
    cprintf("memory management: %s\n", pmm_manager->name);
    pmm_manager->init();
}

// 调用管理器的 init_memmap，建立空闲内存对应的 Page 描述符
static void init_memmap(struct Page *base, size_t n) {
    pmm_manager->init_memmap(base, n);
}

// 调用管理器分配连续的 n 个页面
struct Page *alloc_pages(size_t n) {
    return pmm_manager->alloc_pages(n);
}

// 调用管理器释放连续的 n 个页面
void free_pages(struct Page *base, size_t n) {
    pmm_manager->free_pages(base, n);
}

// 获取当前空闲页数量
size_t nr_free_pages(void) {
    return pmm_manager->nr_free_pages();
}

// lab2 任务一：物理内存初始化；学号：2412891
/*
 * 根据设备树发现物理内存范围，并把未被 OpenSBI、内核镜像和 Page 数组占用的
 * 部分建立为初始空闲区。
 */
static void page_init(void) {
    extern char end[];

    /* DTB 描述的是物理地址范围，而不是虚拟地址。 */
    uint64_t mem_base = get_memory_base();
    uint64_t mem_size = get_memory_size();
    if (mem_base == 0 || mem_size == 0 ||
        mem_size > (~(uint64_t)0 - mem_base)) {
        panic("invalid physical memory range from device tree");
    }

    uint64_t mem_end = mem_base + mem_size;
    if (mem_end <= mem_base || PPN(mem_end) <= nbase) {
        panic("physical memory range has no usable pages");
    }

    /* 直接映射关系：内核虚拟地址 KVA = 物理地址 PA + va_pa_offset。 */
    va_pa_offset = PHYSICAL_MEMORY_OFFSET;
    npage = PPN(mem_end);

    /*
     * 每个物理页对应一个 Page 描述符。描述符数组位于内核直接映射区域，
     * 因此自身也会占用物理页，必须在注册空闲区之前标记为保留。
     */
    pages = (struct Page *)ROUNDUP((uintptr_t)end, PGSIZE);
    size_t page_count = npage - nbase;
    for (size_t i = 0; i < page_count; i++) {
        pages[i].flags = 0;
        pages[i].property = 0;
        set_page_ref(&pages[i], 0);
        SetPageReserved(&pages[i]);
        list_init(&pages[i].page_link);
    }

    /* 同时排除内核镜像和描述符数组，防止它们进入空闲内存。 */
    uintptr_t kernel_end_pa = PADDR((uintptr_t)end);
    uintptr_t pages_end_pa = PADDR((uintptr_t)(pages + page_count));
    uintptr_t free_begin = ROUNDUP(kernel_end_pa > pages_end_pa
                                        ? kernel_end_pa : pages_end_pa,
                                    PGSIZE);
    if (free_begin < mem_base) {
        free_begin = ROUNDUP((uintptr_t)mem_base, PGSIZE);
    }
    uintptr_t free_end = ROUNDDOWN((uintptr_t)mem_end, PGSIZE);

    cprintf("physical memory map:\n");
    cprintf("  memory: 0x%016lx, [0x%016lx, 0x%016lx].\n",
            (unsigned long)mem_size, (unsigned long)mem_base,
            (unsigned long)(mem_end - 1));

    /* 只有完整且按页对齐的物理页框才能交给页面分配器。 */
    if (free_begin < free_end) {
        init_memmap(pa2page(free_begin), (free_end - free_begin) / PGSIZE);
    }
}

/* 初始化物理内存管理系统 */
void pmm_init(void) {
    // 物理内存需要按页分配和释放，因此 pmm.h 定义了统一的管理器接口。
    // 先选择并初始化一个管理器，再由它负责后续物理页的分配和回收。
    init_pmm_manager();

    // 探测物理内存范围，保留已经使用的区域，再调用 init_memmap 建立空闲链表。
    page_init();

    // 使用管理器自带检查函数验证分配和释放逻辑。
    check_alloc_page();
    buddy_challenge_check();
    slub_challenge_check();

    extern char boot_page_table_sv39[];
    satp_virtual = (pte_t*)boot_page_table_sv39;
    satp_physical = PADDR(satp_virtual);
    cprintf("satp virtual address: 0x%016lx\nsatp physical address: 0x%016lx\n", satp_virtual, satp_physical);
}

static void check_alloc_page(void) {
    pmm_manager->check();
    cprintf("check_alloc_page() succeeded!\n");
}
