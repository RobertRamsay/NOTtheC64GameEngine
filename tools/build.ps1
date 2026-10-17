# Compile NOTtheC64GameEngine with Igor (GameMaker's build CLI), Windows VM.
#   powershell -File tools\build.ps1                 compile only (PackageZip into %TEMP%), print errors
#   powershell -File tools\build.ps1 -Run            compile and run the game
#   powershell -File tools\build.ps1 -Shot out.png   run the auto-screenshot self-test (docs/ENGINE_DESIGN.md §10)
#        [-Pose "x,y,z,yaw,pitch"]                   camera pose for the shot (noclip)
#   -Config Player                                   build the Player (shipped runtime) instead of the Editor
param([switch]$Run, [string]$Shot = "", [string]$Pose = "", [string]$Config = "Default")
$repo = Split-Path -Parent $PSScriptRoot
$rt = (Get-ChildItem "C:\ProgramData\GameMakerStudio2-LTS2026\Cache\runtimes" -Directory | Sort-Object Name | Select-Object -Last 1).FullName
$user = (Get-ChildItem "$env:APPDATA\GameMakerStudio2-LTS2026" -Directory | Where-Object { $_.Name -match "_\d+$" } | Select-Object -First 1).FullName
$igor = "$rt\bin\igor\windows\x64\Igor.exe"
if (-not (Test-Path $igor)) { throw "Igor not found at $igor" }

$work = Join-Path $env:TEMP "ntc64_build_$Config"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
# Igor zips the parent of --of, so the log lives outside it
New-Item -ItemType Directory "$work\pkg\out" | Out-Null
$log = Join-Path $env:TEMP "ntc64_build_$Config.log"

$target = "PackageZip"
$of = "$work\pkg\out"
if ($Run -or $Shot -ne "")
{
    # Run wants --of to be the data file itself
    $target = "Run"
    $of = "$work\pkg\NOTtheC64GameEngine.win"
}
if ($Shot -ne "")
{
    $env:NTC64_AUTOSHOT = [IO.Path]::GetFullPath($Shot)
    $env:NTC64_AUTOSHOT_POSE = $Pose
}
else
{
    $env:NTC64_AUTOSHOT = ""
    $env:NTC64_AUTOSHOT_POSE = ""
}

& $igor -j=8 --project="$repo\NOTtheC64GameEngine.yyp" --user="$user" --runtimePath="$rt" --temp="$work\tmp" --cache="$work\cache" --of="$of" --tf="$work\NOTtheC64GameEngine.zip" --runtime=VM --config="$Config" -- Windows $target > $log 2>&1

$errs = Select-String -Path $log -Pattern "(?i)\berror\b|exception" | Where-Object { $_.Line -notmatch "0 error" }
"--- errors: " + ($errs | Measure-Object).Count + "   (log: $log)"
$errs | Select-Object -First 40 | ForEach-Object { $_.Line }
Select-String -Path $log -Pattern "AUTOSHOT|NOTtheC64GameEngine (Editor|Player):|tex_create" | ForEach-Object { $_.Line }
