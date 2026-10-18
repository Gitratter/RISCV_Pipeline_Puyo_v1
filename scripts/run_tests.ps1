param([string]$Iverilog='iverilog',[string]$Vvp='vvp',[string]$IverilogBase='', [switch]$Baseline)
$ErrorActionPreference='Stop'
if($IverilogBase){$IverilogBase=(Resolve-Path -LiteralPath $IverilogBase).ProviderPath}
$projectRoot=Split-Path -Parent $PSScriptRoot
$build=Join-Path $projectRoot 'build/sim'
New-Item -ItemType Directory -Force $build | Out-Null
$rtl=(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'rtl') -Recurse -Filter '*.v').FullName | ForEach-Object {$_.Substring($projectRoot.Length+1)}
$tests=(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'sim') -Filter 'tb_*.v' | Sort-Object Name)
Push-Location $projectRoot
try {
    foreach($test in $tests) {
        $out=Join-Path 'build/sim' ($test.BaseName+'.vvp')
        $argsCompile=@('-g2012','-Wall','-DSIMULATION','-I','sim','-s',$test.BaseName,'-o',$out)
        if($IverilogBase){$argsCompile+=@('-B',$IverilogBase)}
        & $Iverilog @argsCompile @rtl ('sim/'+$test.Name)
        if($LASTEXITCODE -ne 0){throw "Compile failed: $($test.Name), exit=$LASTEXITCODE"}
        # Normalize generated Icarus Windows VPI paths, not source files.
        [IO.File]::WriteAllText($out,[IO.File]::ReadAllText($out).Replace('\','/'))
        & $Vvp -M - $out 2>&1 | Tee-Object -FilePath (Join-Path $build ($test.BaseName+'.log'))
        if($LASTEXITCODE -ne 0){throw "Test failed: $($test.Name)"}
    }
    if($Baseline) {
        & (Join-Path $projectRoot 'baseline_v3/scripts/run_tests.ps1') -Iverilog $Iverilog -Vvp $Vvp -IverilogBase $IverilogBase
    }
    Write-Host "PASS: $($tests.Count) integrated project testbenches"
} finally {Pop-Location}
