param(
    [switch]$RunQemu
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Make = Join-Path $PSScriptRoot 'host\make.exe'
$Toolchain = 'C:\Users\LENOVO\AppData\Local\Programs\riscv-dl\xpack-riscv-none-elf-gcc-15.2.0-1\bin'
$Qemu = 'C:\Users\LENOVO\AppData\Local\Programs\qemu62\qemu-system-riscv64.exe'

if (!(Test-Path $Make)) { throw "Missing local GNU Make: $Make" }
if (!(Test-Path (Join-Path $Toolchain 'riscv-none-elf-gcc.exe'))) {
    throw "Missing RISC-V toolchain: $Toolchain"
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
    & $Make -j2 GCCPREFIX=riscv-none-elf- SHELL=C:/Windows/System32/cmd.exe MKDIR=mkdir
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    if ($RunQemu) {
        & $Qemu -machine virt -nographic -bios default -kernel bin/ucore.img
    }
}
finally {
    Pop-Location
}
