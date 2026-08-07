# Godot 테스트 씬을 헤드리스로 돌리고 실패를 시끄럽게(exit 1) 알리는 러너.
# GDScript assert()는 헤드리스에서 실행을 멈추지 않으므로 stderr/stdout을 직접 판정한다.
param([string]$Scene = "res://tests/test_core.tscn", [string]$Marker = "ALL CORE TESTS PASS", [int]$TimeoutSec = 180)

$ErrorActionPreference = "Stop"

# 콘솔 서브시스템 exe만 stdout 리다이렉트가 확실히 동작한다 (win64.exe는 GUI 서브시스템).
$Godot = "C:\Users\ui2030\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64_console.exe"
$Project = "C:\Users\ui2030\Documents\cozy-vale"

$outFile = [IO.Path]::GetTempFileName()
$errFile = [IO.Path]::GetTempFileName()

# PS 5.1에서 네이티브 exe에 2>&1을 쓰면 NativeCommandError로 감싸므로 Start-Process 리다이렉트를 쓴다.
$proc = Start-Process -FilePath $Godot `
    -ArgumentList @("--headless", "--path", $Project, $Scene) `
    -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
    -PassThru -NoNewWindow
$null = $proc.Handle  # PS 5.1: -Wait 없이 띄우면 핸들을 미리 안 잡아둘 경우 ExitCode가 빈 값으로 읽힘(실증)

# e2e에서 assert가 깨지면 코루틴이 중단돼 quit()에 못 가고 Godot이 영원히 돈다(실증) — 타임아웃이 fail-loud의 마지노선.
$timedOut = -not $proc.WaitForExit($TimeoutSec * 1000)
if ($timedOut) { $proc.Kill(); $proc.WaitForExit() }

$stdout = @(Get-Content $outFile -ErrorAction SilentlyContinue)
$stderr = @(Get-Content $errFile -ErrorAction SilentlyContinue)
Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue

# 판정 4종. 'Parse JSON failed', 'is_inside_tree()' 같은 의도된 소음은 어느 패턴에도 안 걸린다.
$failures = @()
$evidence = @()

$assertLines = @($stderr | Where-Object { $_ -match "Assertion failed" })
if ($assertLines.Count -gt 0) {
    $failures += "stderr에 'Assertion failed' ($($assertLines.Count)건)"
    $evidence += $assertLines | Select-Object -First 5
}

$scriptErrLines = @($stderr | Where-Object { $_ -match "^SCRIPT ERROR:" })
if ($scriptErrLines.Count -gt 0) {
    $failures += "stderr에 SCRIPT ERROR ($($scriptErrLines.Count)건)"
    $evidence += $scriptErrLines | Select-Object -First 5
}

if (-not ($stdout | Where-Object { $_ -match [regex]::Escape($Marker) })) {
    $failures += "stdout에 '$Marker' 없음 (끝까지 못 감)"
    $evidence += $stdout | Select-Object -Last 5
}

if ($timedOut) {
    $failures += "타임아웃 ${TimeoutSec}초 — 테스트가 quit()에 못 감(assert 실패 시 전형)"
} elseif ($proc.ExitCode -ne 0) {
    $failures += "Godot 종료 코드 $($proc.ExitCode)"
}

if ($failures.Count -eq 0) {
    Write-Output "PASS"
    exit 0
}

Write-Output "FAIL: $Scene"
$failures | ForEach-Object { Write-Output "  - $_" }
if ($evidence.Count -gt 0) {
    Write-Output "--- 관련 출력 ---"
    $evidence | Select-Object -First 12 | ForEach-Object { Write-Output "  $_" }
}
exit 1
