@echo off
for /f "tokens=2 delims=:" %%P in ('tasklist /fi "IMAGENAME eq qemu-system-riscv64.exe" /fo list ^| findstr /b "PID:"') do set QEMU_PID=%%P
set QEMU_PID=%QEMU_PID: =%
"D:\os\msys2\msys64\mingw64\bin\gdb.exe" -q -batch -ex "file D:/os/lab2/qemu-4.1.1/build-riscv-debug/riscv64-softmmu/qemu-system-riscv64.exe" -ex "attach %QEMU_PID%" --command="D:/os/lab2/lab2_new/tools/gdb_qemu_pagewalk.gdb"
