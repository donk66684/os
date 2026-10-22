# RISC-V GDB：观察 ucore 开启 Sv39 后的 SATP 与三级页表索引
set pagination off
set confirm off
# 架构、符号文件和远程连接由启动脚本在加载本文件前完成。

# check_alloc_page 位于 kern_init 完成 pmm_init 之后，便于观察已经初始化的内核状态。
break check_alloc_page
continue

echo \n===== guest breakpoint =====\n
printf "PC = 0x%016lx\n", $pc
info registers satp
x/8i $pc

# 以当前 PC 作为待观察的虚拟地址，拆出 Sv39 的 VPN[2:0] 和页内偏移。
# GDB 在此目标上显示的 PC 可能省略 Sv39 高位，按内核直接映射区补齐规范地址。
set $va = ((unsigned long)0xffffffffc0000000 + ((unsigned long)$pc & (unsigned long)0x3fffffff))
set $vpn2 = (($va >> 30) & (unsigned long)0x1ff)
set $vpn1 = (($va >> 21) & (unsigned long)0x1ff)
set $vpn0 = (($va >> 12) & (unsigned long)0x1ff)
set $offset = ($va & (unsigned long)0xfff)
set $root_ppn = ((unsigned long)$satp & (unsigned long)0x3fffffffffffff)
set $root_pa = $root_ppn << 12
set $root_va = ((unsigned long)0xffffffff40000000 + $root_pa)

printf "VA = 0x%016lx\n", $va
printf "VPN2 = 0x%03lx, VPN1 = 0x%03lx, VPN0 = 0x%03lx\n", $vpn2, $vpn1, $vpn0
printf "offset = 0x%03lx\n", $offset
printf "SATP.PPN = 0x%lx, root_pa = 0x%016lx\n", $root_ppn, $root_pa
printf "root_va = 0x%016lx\n", $root_va
printf "L2 PTE address = 0x%016lx\n", $root_va + $vpn2 * 8
x/gx $root_va + $vpn2 * 8

echo \n===== continue =====\n
continue
quit
