param(
    [int]$Port = 2363,
    [string]$QemuRoot = '',
    [string]$Gdb = ''
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LabRoot = Split-Path -Parent $ProjectRoot
if (!$QemuRoot) { $QemuRoot = Join-Path $LabRoot 'qemu-4.1.1\build-riscv-debug' }
$Qemu = Join-Path $QemuRoot 'riscv64-softmmu\qemu-system-riscv64.exe'
if (!$Gdb) { $gdbCommand = Get-Command 'gdb.exe' -ErrorAction SilentlyContinue; if ($null -ne $gdbCommand) { $Gdb = $gdbCommand.Source } }
$Kernel = Join-Path $ProjectRoot 'bin\kernel'
$Image = Join-Path $ProjectRoot 'bin\ucore.img'
$QemuGdb = $Qemu -replace '\\', '/'
$KernelGdb = $Kernel -replace '\\', '/'
$LogDir = Join-Path $LabRoot 'report\logs'
$HostLog = Join-Path $LogDir 'qemu_source_gdb_host.txt'
$HostErr = Join-Path $LogDir 'qemu_source_gdb_host.stderr.txt'
$GuestLog = Join-Path $LogDir 'qemu_source_gdb_guest.txt'
$SerialLog = Join-Path $LogDir 'qemu_source_gdb_serial.txt'
$PidFile = Join-Path $LogDir 'qemu_pid_for_gdb.txt'

foreach ($path in @($Qemu, $Gdb, $Kernel, $Image)) {
    if (!(Test-Path $path)) { throw "找不到调试所需文件：$path" }
}
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$oldPath = $env:Path
$env:Path = "$(Split-Path -Parent $Gdb);$oldPath"
$qemuHandle = $null
$hostGdbProcess = $null
try {
    $bios = Join-Path $QemuRoot 'pc-bios\opensbi-riscv64-virt-fw_jump.bin'
    $qemuArgs = @('-machine', 'virt', '-nographic', '-bios', $bios, '-kernel', $Image, '-S', '-gdb', "tcp::$Port", '-monitor', 'none', '-serial', "file:$SerialLog")
    $qemuHandle = Start-Process -FilePath $Qemu -ArgumentList ($qemuArgs -join ' ') -WorkingDirectory $QemuRoot -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 1200

    # 宿主机 GDB 先附加 QEMU、设置源码断点并继续；随后来宾 GDB 才会让 CPU 执行。
    $qpid = $qemuHandle.Id
    if (!$qpid) { throw "QEMU PID not found" }
    $hostCommandFile = Join-Path $LogDir 'qemu_host_commands.gdb'
    Set-Content -LiteralPath $hostCommandFile -Value @(
        'set pagination off'
        'set confirm off'
        'set breakpoint pending on'
        "file $($Qemu -replace '\\','/')"
        "attach $qpid"
        "source $((Join-Path $ProjectRoot 'tools\gdb_qemu_pagewalk.gdb') -replace '\\','/')"
    )
    $hostGdbProcess = Start-Process -FilePath $Gdb -ArgumentList "-q -batch --command=$($hostCommandFile -replace '\\','/')" -RedirectStandardOutput $HostLog -RedirectStandardError $HostErr -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 1200

    $guestArgs = @('-q', '-batch', '-ex', "file $KernelGdb", '-ex', "target remote :$Port", '-ex', 'break check_alloc_page', '-ex', 'continue', '-ex', 'info registers satp', '-ex', 'x/6i $pc', '-ex', 'quit')
    & $Gdb @guestArgs 2>&1 | Tee-Object -FilePath $GuestLog
    if ($LASTEXITCODE -ne 0) { throw "来宾 GDB 失败，退出码：$LASTEXITCODE" }
}
finally {
    if ($null -ne $hostGdbProcess -and !$hostGdbProcess.HasExited) { Stop-Process -Id $hostGdbProcess.Id -Force }
    if ($null -ne $qemuHandle -and !$qemuHandle.HasExited) { Stop-Process -Id $qemuHandle.Id -Force }
    $env:Path = $oldPath
}
