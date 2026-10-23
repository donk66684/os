param(
    [switch]$RunQemu
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Make = Join-Path $PSScriptRoot 'host\make.exe'
$toolchainCommand = Get-Command 'riscv-none-elf-gcc.exe' -ErrorAction SilentlyContinue
if ($null -eq $toolchainCommand) { $toolchainCommand = Get-Command 'riscv64-unknown-elf-gcc.exe' -ErrorAction SilentlyContinue }
$Toolchain = if ($null -ne $toolchainCommand) { Split-Path -Parent $toolchainCommand.Source } else { $null }
$qemuCommand = Get-Command 'qemu-system-riscv64.exe' -ErrorAction SilentlyContinue
$Qemu = if ($null -ne $qemuCommand) { $qemuCommand.Source } else { $null }

if (!(Test-Path $Make)) { throw "Missing local GNU Make: $Make" }
if ($null -eq $Toolchain) {
    throw "Missing RISC-V GCC. Install riscv-none-elf-gcc or riscv64-unknown-elf-gcc and add its bin directory to PATH."
}

$env:Path = "$($PSScriptRoot)\host;$Toolchain;$env:Path"
$dirs = @(
    'obj', 'obj\libs', 'obj\kern', 'obj\kern\init', 'obj\kern\libs',
    'obj\kern\debug', 'obj\kern\driver', 'obj\kern\mm', 'obj\kern\test', 'bin'
)
foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Root $dir) | Out-Null
}

Push-Location $Root
try {
    $prefix = if (Test-Path (Join-Path $Toolchain 'riscv-none-elf-gcc.exe')) { 'riscv-none-elf-' } else { 'riscv64-unknown-elf-' }
    & $Make -j2 GCCPREFIX=$prefix SHELL=C:/Windows/System32/cmd.exe MKDIR=mkdir
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    if ($RunQemu) {
        if ($null -eq $Qemu) { throw "Missing qemu-system-riscv64.exe; install QEMU or add it to PATH." }
        & $Qemu -machine virt -nographic -bios default -kernel bin/ucore.img
    }
}
finally {
    Pop-Location
}
