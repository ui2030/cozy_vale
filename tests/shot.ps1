# 룩데브 컷 한 장. `-Args` = world.gd 하네스 토큰(-- 뒤로 그대로 전달).
# 예: .\tests\shot.ps1 -CmdArgs @("v_hall","hour","12","weather","clear","out","wall/x.png")
param([string[]]$CmdArgs, [int]$TimeoutSec = 120)
$ErrorActionPreference = "Stop"
$Godot = "C:\Users\ui2030\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64_console.exe"
$Project = "C:\Users\ui2030\Documents\cozy-vale"
$outFile = [IO.Path]::GetTempFileName()
$errFile = [IO.Path]::GetTempFileName()
$argList = @("--path", $Project, "--") + $CmdArgs
$proc = Start-Process -FilePath $Godot -ArgumentList $argList `
    -RedirectStandardOutput $outFile -RedirectStandardError $errFile -PassThru -NoNewWindow
$null = $proc.Handle
if (-not $proc.WaitForExit($TimeoutSec * 1000)) { $proc.Kill(); $proc.WaitForExit(); Write-Output "TIMEOUT" }
Get-Content $outFile -ErrorAction SilentlyContinue | Where-Object { $_ -match "saved|shot:" }
Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
