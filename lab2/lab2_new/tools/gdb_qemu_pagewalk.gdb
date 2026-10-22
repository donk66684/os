# 宿主机 GDB：附加带调试信息的 QEMU 进程后使用。
# 用法：gdb -q -x tools/gdb_qemu_pagewalk.gdb --args <调试版 qemu 参数>
set pagination off
set confirm off
set breakpoint pending on

# QEMU 受到 SIGPIPE 时不应被 GDB 停住。
handle SIGPIPE nostop noprint

# QEMU 4.1.1 的 RISC-V 地址翻译入口和页表遍历函数。
break riscv_cpu_tlb_fill
break get_physical_address

# 命中后打印关键参数；随后继续运行，避免每次普通访存都人工确认。
commands 1
silent
printf "[QEMU] TLB 未命中：进入 riscv_cpu_tlb_fill\n"
printf "pc = 0x%lx\n", retaddr
continue
end

commands 2
silent
printf "[QEMU] 开始页表查询：进入 get_physical_address\n"
printf "address = 0x%lx, access_type = %d, mmu_idx = %d\n", address, access_type, mmu_idx
bt 5
continue
end

continue
