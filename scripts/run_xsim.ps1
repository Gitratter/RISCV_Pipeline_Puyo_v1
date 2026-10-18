param([string]$VivadoRoot='C:/AMDDesignTools/2025.2/Vivado')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'run_vivado.ps1') -VivadoRoot $VivadoRoot -EnvironmentOnly
$root=Split-Path -Parent $PSScriptRoot
$bin="$env:XILINX_VIVADO/bin/unwrapped/win64.o"
Push-Location $root
try {
    New-Item -ItemType Directory -Force build/xsim | Out-Null
    $rtl=@((Get-ChildItem rtl -Recurse -Filter '*.v').FullName)
    $tests=@(Get-ChildItem sim -Filter 'tb_*.v' | Sort-Object Name)
    & "$bin/xvlog.exe" --sv -d SIMULATION -i sim --log build/xsim/compile.log @rtl @($tests.FullName)
    if($LASTEXITCODE -ne 0){throw 'XSim compilation failed'}
    foreach($test in $tests) {
        $name=$test.BaseName
        & "$bin/xelab.exe" "work.$name" --mt off -s "puyo_$name" --log "build/xsim/$name.elab.log"
        if($LASTEXITCODE -ne 0){throw "XSim elaboration failed: $name"}
        & "$bin/xsim.exe" "puyo_$name" -runall -onerror quit -onfinish quit -log "build/xsim/$name.log"
        if($LASTEXITCODE -ne 0){throw "XSim run failed: $name"}
        $log=Get-Content -Raw -LiteralPath "build/xsim/$name.log"
        if($log -notmatch 'PASS' -or $log -match '(?im)^Fatal:|^Error:|^ERROR:') {throw "Missing PASS or assertion failure: $name"}
    }
    Write-Host "PASS: $($tests.Count) XSim project testbenches"
} finally {Pop-Location}
