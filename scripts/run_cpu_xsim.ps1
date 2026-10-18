param([string]$VivadoRoot='C:/AMDDesignTools/2025.2/Vivado')
$ErrorActionPreference='Stop'
$VivadoRoot=(Resolve-Path -LiteralPath $VivadoRoot).ProviderPath.Replace('\','/')
$projectRoot=Split-Path -Parent $PSScriptRoot
$env:XILINX_VIVADO=$VivadoRoot
$env:RDI_APPROOT=$VivadoRoot
$env:HDI_APPROOT=$VivadoRoot
$env:RDI_DATADIR="$VivadoRoot/data"
$env:RDI_BINDIR="$VivadoRoot/bin"
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
$buildDir=Join-Path $projectRoot '.cpu_xsim'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$sources=@(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'rtl/cpu') -Filter '*.v' | Sort-Object Name | ForEach-Object { $_.FullName })
$sources+=Join-Path $projectRoot 'rtl/platform/PipelineMemoryV31.v'
$tests=@(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'sim/cpu_regression') -Filter 'tb_cpu_*.v' | Sort-Object Name)
$tests+=Get-Item -LiteralPath (Join-Path $projectRoot 'sim/tb_cpu_platform.v')
Push-Location $buildDir
try {
    $compileArgs=@('-sv','--work','work','-i',(Join-Path $projectRoot 'sim'),'-log','compile.log')+$sources+@($tests | ForEach-Object {$_.FullName})
    & "$VivadoRoot/bin/unwrapped/win64.o/xvlog.exe" @compileArgs
    if($LASTEXITCODE -ne 0) {throw 'XSim compilation failed. See .cpu_xsim/compile.log'}
    foreach($test in $tests) {
        $name=$test.BaseName
        Write-Host "[elaborate] $name"
        & "$VivadoRoot/bin/unwrapped/win64.o/xelab.exe" "work.$name" -s $name -debug typical -log "$name.elab.log"
        if($LASTEXITCODE -ne 0) {throw "XSim elaboration failed: $name"}
        Write-Host "[simulate] $name"
        & "$VivadoRoot/bin/unwrapped/win64.o/xsim.exe" $name -runall -onfinish quit -log "$name.sim.log"
        if($LASTEXITCODE -ne 0) {throw "XSim simulation failed: $name"}
        $result=Get-Content -Raw -LiteralPath "$name.sim.log"
        if($result -match '(?m)(FATAL:|Fatal:|\[FAIL\])' -or $result -notmatch 'PASS:') {
            throw "XSim test did not report a clean PASS: $name"
        }
    }
    Write-Host 'PASS: all 12 v3.1 CPU tests (Vivado XSim)'
} finally {Pop-Location}
