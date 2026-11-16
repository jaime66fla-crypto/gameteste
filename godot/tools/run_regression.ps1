param(
    [Parameter(Mandatory=$true)][string]$Godot
)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path $PSScriptRoot -Parent
$logPath = Join-Path $projectPath '.godot/regression-polyy-rokoko'
New-Item -ItemType Directory -Force -Path $logPath | Out-Null
$previousSelectionPath = $env:CAMPO_CHARACTER_TEST_PATH
$env:CAMPO_CHARACTER_TEST_PATH = 'user://regression_default_original_' + $PID + '.cfg'
$results = @()
try {
    $cases = @(Get-ChildItem -LiteralPath (Join-Path $projectPath 'tests') -Filter '*.gd' | Sort-Object Name | ForEach-Object { @{Name=$_.BaseName; Script=('tests/'+$_.Name); Extra=@()} })
    $cases += @{Name='sniper_scope_swat'; Script='tests/sniper_scope.gd'; Extra=@('--','--swat')}
    foreach ($case in $cases) {
        $outPath = Join-Path $logPath ($case.Name+'.stdout.log')
        $errPath = Join-Path $logPath ($case.Name+'.stderr.log')
        $arguments = @('--headless','--path','.','--script',$case.Script)+$case.Extra
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $process = Start-Process -FilePath $Godot -ArgumentList $arguments -WorkingDirectory $projectPath -WindowStyle Hidden -PassThru -RedirectStandardOutput $outPath -RedirectStandardError $errPath
        # Keep a process handle open: Windows PowerShell can otherwise expose a
        # null ExitCode after WaitForExit on Start-Process -PassThru results.
        $processHandle = $process.Handle
        $timedOut = -not $process.WaitForExit(90000)
        if ($timedOut) { $process.Kill(); $process.WaitForExit() }
        $stdout = [IO.File]::ReadAllText($outPath)
        $stderr = [IO.File]::ReadAllText($errPath)
        $passed = (-not $timedOut) -and $process.ExitCode -eq 0 -and $stdout -match 'PASS' -and $stderr -notmatch 'SCRIPT ERROR'
        $results += [PSCustomObject]@{Test=$case.Name; Passed=$passed; ExitCode=$process.ExitCode; TimedOut=$timedOut; Seconds=[Math]::Round($watch.Elapsed.TotalSeconds,2); Stdout=$stdout; Stderr=$stderr}
        Write-Output ($case.Name+': '+$(if ($passed) {'PASS'} else {'FAIL'})+' ('+$process.ExitCode+')')
        $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $logPath 'results.json') -Encoding UTF8
    }
} finally {
    $env:CAMPO_CHARACTER_TEST_PATH = $previousSelectionPath
}
$failed = @($results | Where-Object { -not $_.Passed })
Write-Output ('RESULT: '+($results.Count-$failed.Count)+'/'+$results.Count+' passed')
if ($failed.Count -gt 0) { exit 1 }
