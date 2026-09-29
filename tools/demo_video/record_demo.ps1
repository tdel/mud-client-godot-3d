# Enregistre la vidéo de démo (tools/demo_video/DemoVideo.tscn) avec Movie Maker, puis la monte
# en MP4 (H.264 + AAC) : coupe du chargement initial, accélération légère, fondus d'entrée/sortie.
#
# Usage : powershell -ExecutionPolicy Bypass -File tools/demo_video/record_demo.ps1 [-Speed 1.25] [-Width 1920 -Height 1080]
# Sortie : tools/demo_video/out/demo.mp4 (dossier ignoré par git et par l'import Godot).
#
# Movie Maker rend à pas fixe (-RecordFps images par seconde de jeu) : lue à RecordFps * Speed
# images/s, la vidéo est accélérée de Speed sans perdre ni dupliquer d'image (48 x 1.25 = 60).
# ffmpeg vient du paquet Python imageio-ffmpeg (via uv), comme les autres outils du projet.
param(
    [double]$Speed = 1.25,
    [int]$RecordFps = 48,
    [int]$Width = 1920,
    [int]$Height = 1080,
    [string]$Godot = "C:\Users\thoma\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
$project = (Resolve-Path "$PSScriptRoot\..\..").Path
$outDir = Join-Path $PSScriptRoot "out"
New-Item -ItemType Directory -Force $outDir | Out-Null
foreach ($ignore in @(".gdignore", ".gitignore")) {
    $path = Join-Path $outDir $ignore
    if (-not (Test-Path $path)) { Set-Content -Path $path -Value "*" -Encoding ascii }
}
$raw = Join-Path $outDir "raw.avi"
$final = Join-Path $outDir "demo.mp4"

# Taille de fenêtre (Movie Maker ignore --resolution) et qualité MJPEG (0.75 par défaut, trop
# compressé pour un remontage) : réglages projet passés par un override.cfg temporaire, retiré aussitôt après.
$override = Join-Path $project "override.cfg"
if (Test-Path $override) { throw "override.cfg existe déjà : $override" }
Set-Content -Path $override -Encoding ascii -Value "[display]`nwindow/size/window_width_override=$Width`nwindow/size/window_height_override=$Height`n[editor]`nmovie_writer/mjpeg_quality=0.97"
try {
    # Godot écrit ses avertissements sur stderr : sous PowerShell 5.1, ils ne doivent pas
    # interrompre le script.
    $ErrorActionPreference = "Continue"
    $log = & $Godot --path $project --resolution "${Width}x${Height}" --fixed-fps $RecordFps `
        --write-movie $raw res://tools/demo_video/DemoVideo.tscn 2>&1 | ForEach-Object { "$_" }
} finally {
    Remove-Item $override -Force
    $ErrorActionPreference = "Stop"
}
$start = [double](($log | Select-String "DEMO_START_SEC=([0-9.]+)").Matches[0].Groups[1].Value)
$end = [double](($log | Select-String "DEMO_END_SEC=([0-9.]+)").Matches[0].Groups[1].Value)
$log | Select-String "frames at|recorded in" | ForEach-Object { Write-Host $_ }

$ffmpeg = (& uv run --quiet --with imageio-ffmpeg python -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())").Trim()
$inv = [System.Globalization.CultureInfo]::InvariantCulture
$length = ($end - $start) / $Speed
$fadeOut = [Math]::Max($length - 0.6, 0.0)
$outFps = $RecordFps * $Speed
$vf = [string]::Format($inv, "setpts=(PTS-STARTPTS)/{0},fps={1},fade=t=in:st=0:d=0.4,fade=t=out:st={2:0.###}:d=0.6,format=yuv420p", $Speed, $outFps, $fadeOut)
$af = [string]::Format($inv, "asetpts=PTS-STARTPTS,atempo={0},afade=t=in:st=0:d=0.3,afade=t=out:st={1:0.###}:d=0.6", $Speed, $fadeOut)
$ss = $start.ToString("0.###", $inv)
$t = ($end - $start).ToString("0.###", $inv)
& $ffmpeg -y -loglevel error -ss $ss -t $t -i $raw -vf $vf -af $af -c:v libx264 -preset slow -crf 22 -maxrate 16M -bufsize 32M `
    -c:a aac -b:a 192k -movflags +faststart $final
if ($LASTEXITCODE -ne 0) { throw "ffmpeg a échoué" }
Remove-Item $raw
Write-Host ([string]::Format($inv, "Vidéo : {0} ({1:0.0} s)", $final, $length))
