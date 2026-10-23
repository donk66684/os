set pagination off
set confirm off
set breakpoint pending on
handle SIGPIPE nostop noprint
set $walk_count = 0
set $fill_count = 0
break /home/kali123/qemu-6.2.0/target/riscv/cpu_helper.c:409
commands
  silent
  set $walk_count = $walk_count + 1
  if $walk_count <= 8
    printf "[QEMU-6.2] get_physical_address: VA=0x%lx access=%d mmu_idx=%d\n", addr, access_type, mmu_idx
    if $walk_count == 1
      bt 5
    end
  end
  continue
end
break /home/kali123/qemu-6.2.0/target/riscv/cpu_helper.c:818
commands
  silent
  set $fill_count = $fill_count + 1
  if $fill_count <= 8
    printf "[QEMU-6.2] riscv_cpu_tlb_fill: VA=0x%lx size=%d mmu_idx=%d\n", address, size, mmu_idx
    if $fill_count == 1
      bt 5
    end
  end
  continue
end
continue
