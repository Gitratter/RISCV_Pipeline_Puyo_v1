param(
    [string]$Iverilog = "iverilog",
    [string]$Vvp = "vvp",
    [string]$IverilogBase = ""
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ($IverilogBase -ne "") { $IverilogBase = (Resolve-Path -LiteralPath $IverilogBase).ProviderPath }
$simDir = Join-Path $root "sim"
$buildDir = Join-Path $root ".sim_build"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$sources = @(Get-ChildItem -LiteralPath (Join-Path $root "rtl/cpu") -Filter "*.v" | Sort-Object Name | ForEach-Object { $_.FullName })
$sources += Join-Path $root "rtl/platform/PipelineMemoryV31.v"
$tests = @(Get-ChildItem -LiteralPath (Join-Path $simDir "cpu_regression") -Filter "tb_cpu_*.v" | Sort-Object Name)
$tests += Get-Item -LiteralPath (Join-Path $simDir "tb_cpu_platform.v")
Push-Location $root
try { foreach ($testFile in $tests) {
    $test = $testFile.BaseName
    $outputFile = Join-Path $buildDir ($test + ".vvp")
    $compileArgs = @("-g2012", "-Wall", "-I", $simDir, "-s", $test, "-o", $outputFile)
    if ($IverilogBase -ne "") { $compileArgs += @("-B", $IverilogBase) }
    $compileArgs += $sources
    $compileArgs += $testFile.FullName
    Write-Host "[compile] $test"
    & $Iverilog @compileArgs
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $test" }
    # Mechanical fix for portable Windows Icarus VPI search-path escaping.
    $vvpImage = [System.IO.File]::ReadAllText($outputFile).Replace("\", "/")
    [System.IO.File]::WriteAllText($outputFile, $vvpImage)
    Write-Host "[run] $test"
    & $Vvp -M - $outputFile
    if ($LASTEXITCODE -ne 0) { throw "Simulation failed: $test" }
} } finally { Pop-Location }
Write-Host "PASS: all 12 v3.1 CPU tests"
