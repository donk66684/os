set pagination off
set confirm off
set breakpoint pending on
handle SIGPIPE nostop noprint
set args -machine virt -nographic -bios /mnt/d/Study/OS/.tools/qemu/riscv-qemu-5.1.0-2020.08.1-x86_64-w64-mingw32/bin/opensbi-riscv64-virt-fw_jump.bin -kernel /mnt/d/Study/OS/Lab/Lab2/lab2_new/bin/ucore.img -S -gdb tcp::1234 -monitor none -serial file:/mnt/d/Study/OS/Lab/Lab2/report/logs/qemu_source_gdb_serial_new.txt
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
run
