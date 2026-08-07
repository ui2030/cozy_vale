# 코어 + e2e 씬 전체를 run_core.ps1로 순차 실행. 하나라도 실패하면 거기서 멈춘다.
$ErrorActionPreference = "Stop"
$runner = Join-Path $PSScriptRoot "run_core.ps1"

# 씬 -> 성공 마커. 마커는 각 .gd의 실제 print 문 앞부분 고정 문자열.
$suite = @(
    @("test_core",     "ALL CORE TESTS PASS"),
    @("e2e_interact",  "E2E INTERACT PASS"),
    @("e2e_fishing",   "E2E FISHING PASS"),
    @("e2e_prompts",   "E2E PROMPTS PASS"),
    @("e2e_inventory", "E2E INVENTORY PASS"),
    @("e2e_schedule",  "E2E SCHEDULE PASS"),
    @("e2e_marriage",  "E2E MARRIAGE PASS"),
    @("e2e_interior",  "E2E INTERIOR PASS"),
    @("e2e_beach",     "E2E BEACH PASS"),
    @("e2e_face",      "E2E FACE PASS")
)

foreach ($t in $suite) {
    $out = & $runner -Scene "res://tests/$($t[0]).tscn" -Marker $t[1]
    if ($LASTEXITCODE -ne 0) {
        Write-Output "FAIL: $($t[0])"
        $out | ForEach-Object { Write-Output "  $_" }
        exit 1
    }
    Write-Output "OK   $($t[0])"
}

Write-Output "ALL SUITES PASS ($($suite.Count)개)"
exit 0
