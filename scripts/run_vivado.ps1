param([string]$VivadoRoot='C:/AMDDesignTools/2025.2/Vivado', [switch]$EnvironmentOnly)
$ErrorActionPreference='Stop'
$VivadoRoot=(Resolve-Path -LiteralPath $VivadoRoot).ProviderPath.Replace('\','/')
$projectRoot=Split-Path -Parent $PSScriptRoot
$env:XILINX_VIVADO=$VivadoRoot
$env:RDI_APPROOT=$VivadoRoot
$env:HDI_APPROOT=$VivadoRoot
$env:RDI_DATADIR="$VivadoRoot/data"
$env:RDI_BINDIR="$VivadoRoot/bin"
$env:RDI_BINROOT="$VivadoRoot/bin"
$env:RDI_BASEROOT=(Split-Path -Parent $VivadoRoot).Replace('\','/')
$env:RDI_PLATFORM='win64'
$env:RDI_OPT_EXT='.o'
$env:XILINX_LOCAL_USER_DATA='NO'
$env:XILINX_TCLAPP_REPO="$VivadoRoot/data/XilinxTclStore"
$env:TCL_LIBRARY="$VivadoRoot/tps/tcl/tcl8.6"
$env:RDI_BUILD='yes'
$env:RDI_LIBDIR="$VivadoRoot/lib/win64.o"
$env:RT_LIBPATH="$VivadoRoot/scripts/rt/data"
$env:RT_TCL_PATH="$VivadoRoot/scripts/rt/base_tcl/tcl"
$env:SYNTH_COMMON=$env:RT_LIBPATH
$env:RDI_JAVAROOT="$VivadoRoot/tps/win64/jre21.0.5_11"
$env:PATH=("$VivadoRoot/lib/win64.o;$VivadoRoot/bin/unwrapped/win64.o;$VivadoRoot/bin;$VivadoRoot/tps/win64;$VivadoRoot/tps/mingw/6.2.0/win64.o/nt/bin;$VivadoRoot/tps/mingw/6.2.0/win64.o/nt/libexec/gcc/x86_64-w64-mingw32/6.2.0;" -replace '/','\')+$env:PATH
$env:PATH=("$env:RDI_JAVAROOT/bin/server;$env:RDI_JAVAROOT/bin;" -replace '/','\')+$env:PATH
if($EnvironmentOnly){return}
Push-Location $projectRoot
try {
    & "$VivadoRoot/bin/unwrapped/win64.o/vivado.exe" -mode batch -source scripts/vivado_build.tcl -log build_vivado.log -journal build_vivado.jou
    if($LASTEXITCODE -ne 0){throw 'Vivado build failed. See build_vivado.log.'}
} finally {Pop-Location}
