# Diagnostic only: does NOT declare a clean compile PASS for an abnormal exit.
param([Parameter(Mandatory=$true)][string]$Iverilog,
      [Parameter(Mandatory=$true)][string]$Vvp,
      [Parameter(Mandatory=$true)][string]$IverilogBase)
$ErrorActionPreference='Stop'
$IverilogBase=(Resolve-Path -LiteralPath $IverilogBase).ProviderPath
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $run=Join-Path 'build/icarus_diagnostic' (Get-Date -Format 'yyyyMMdd_HHmmss')
    New-Item -ItemType Directory -Force $run | Out-Null
    $rtl=@((Get-ChildItem rtl -Recurse -Filter '*.v').FullName)
    $results=@()
    foreach($tb in @(Get-ChildItem sim -Filter 'tb_*.v' | Sort-Object Name)) {
        $name=$tb.BaseName; $out=Join-Path $run "$name.vvp"
        $compile=@(& $Iverilog -B $IverilogBase -v -g2012 -Wall -DSIMULATION -I sim -s $name -o $out @rtl $tb.FullName 2>&1)
        $compileExit=$LASTEXITCODE
        $compile | Set-Content -LiteralPath (Join-Path $run "$name.compile.log")
        $done=($compile -join "`n") -match 'DONE\.'
        $simExit=$null; $assertionsPassed=$false
        if((Test-Path -LiteralPath $out) -and ($compileExit -eq 0 -or ($compileExit -eq -1073741819 -and $done))) {
            [IO.File]::WriteAllText($out,[IO.File]::ReadAllText($out).Replace('\','/'))
            $result=@(& $Vvp -M - $out 2>&1)
            $simExit=$LASTEXITCODE
            $result | Tee-Object -FilePath (Join-Path $run "$name.run.log")
            $assertionsPassed=($simExit -eq 0 -and ($result -join "`n") -match 'PASS' -and ($result -join "`n") -notmatch 'FATAL:')
        }
        $results += [pscustomobject]@{test=$name; compiler_exit=$compileExit; codegen_done=$done; simulator_exit=$simExit; assertions_passed=$assertionsPassed; clean_compile=($compileExit -eq 0)}
    }
    $results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'results.json')
    $results | Format-Table
    if(@($results | Where-Object {-not $_.assertions_passed}).Count -gt 0){throw 'A simulation assertion run did not pass; see diagnostics.'}
    Write-Warning "Simulation assertions passed; this diagnostic is NOT a clean compiler validation. See $run/results.json"
} finally {Pop-Location}
