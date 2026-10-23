# 宿主机 GDB：附加带调试信息的 QEMU 进程，观察 RISC-V 地址翻译。
# 启动器会先执行 file 和 attach，再加载本文件。
set pagination off
set confirm off
set breakpoint pending on
handle SIGPIPE nostop noprint

# 第一个断点位于页表遍历函数入口，用来观察输入虚拟地址和 SATP。
break get_physical_address
commands
    silent
    set $walk_count = $walk_count + 1
    if $walk_count <= 5
        printf "[QEMU] get_physical_address: addr=0x%lx access=%d mmu_idx=%d satp=0x%lx\n", addr, access_type, mmu_idx, env->satp
        if $walk_count == 1
            bt 6
        end
    end
    continue
end

# 这一行位于 riscv_cpu_tlb_fill 中，get_physical_address 返回后 pa 已经得到。
break target/riscv/cpu_helper.c:459
commands
    silent
    set $fill_count = $fill_count + 1
    if $fill_count <= 5
        printf "[QEMU] TLB miss result: VA=0x%lx ret=%d PA=0x%lx prot=%d\n", address, ret, pa, prot
        if $fill_count == 1
            bt 8
        end
    end
    continue
end

# 默认继续执行；由启动脚本和 RISC-V GDB 控制来宾执行。
set $walk_count = 0
set $fill_count = 0
continue
