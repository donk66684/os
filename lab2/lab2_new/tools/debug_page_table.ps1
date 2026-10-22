param(
    [string]$Qemu = 'C:\Users\LENOVO\AppData\Local\Programs\qemu62\qemu-system-riscv64.exe',
    [string]$Gdb = 'C:\Users\LENOVO\AppData\Local\Programs\riscv-dl\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-gdb.exe',
    [int]$Port = 1234
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path (Split-Path -Parent $Root) 'report\logs'
$Log = Join-Path $LogDir ("gdb_page_table_guest_{0}.txt" -f $Port)
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

if (!(Test-Path $Qemu)) { throw "找不到 QEMU：$Qemu" }
if (!(Test-Path $Gdb)) { throw "找不到 RISC-V GDB：$Gdb" }

Push-Location $Root
try {
    $qemuArgs = @('-machine', 'virt', '-nographic', '-bios', 'default', '-kernel', 'bin/ucore.img', '-S', '-gdb', "tcp::$Port", '-monitor', 'none', '-serial', 'none')
    # Windows PowerShell 对参数数组的转义在部分 QEMU 版本上会丢失 tcp: 参数，合并为一条参数串更稳定。
    $qemuProcess = Start-Process -FilePath $Qemu -ArgumentList ($qemuArgs -join ' ') -PassThru -WindowStyle Hidden
    try {
        Start-Sleep -Milliseconds 800
        & $Gdb '-batch' '-ex' 'set architecture riscv:rv64' '-ex' 'file bin/kernel' '-ex' "target remote :$Port" '-x' 'tools/gdb_page_table.gdb' 2>&1 | Tee-Object -FilePath $Log
        if ($LASTEXITCODE -ne 0) { throw "RISC-V GDB 执行失败，退出码：$LASTEXITCODE" }
    }
    finally {
        if ($null -ne $qemuProcess -and !$qemuProcess.HasExited) { Stop-Process -Id $qemuProcess.Id -Force }
    }
}
finally {
    Pop-Location
}
