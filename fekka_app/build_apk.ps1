# Fekka APK Build Script — auto-increments build number and cycles circle color
$ErrorActionPreference = "Stop"
$env:Path = "C:\flutter\bin;$env:Path"

$buildFile = "lib\build_info.dart"

# Read current build number
$v = 1
if (Test-Path $buildFile) {
    $content = Get-Content $buildFile -Raw
    if ($content -match 'number = (\d+)') {
        $v = [int]$Matches[1] + 1
    }
}

# Cycle color: blue(0) → red(1) → yellow(2) → blue(0) ...
$colorIdx = ($v - 1) % 3
$colors = @('0xFF2196F3', '0xFFE94560', '0xFFFFC107')
$colorNames = @('blue', 'red', 'yellow')
$color = $colors[$colorIdx]

# Write updated build info
@"
/// Auto-generated build info — do not edit manually.
class BuildInfo {
  static const int number = $v;
  static const List<int> colors = [0xFF2196F3, 0xFFE94560, 0xFFFFC107]; // blue, red, yellow
}
"@ | Set-Content $buildFile -NoNewline

Write-Host "═══════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Build #$v  |  Circle: $($colorNames[$colorIdx])" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════" -ForegroundColor Cyan

# Build APK
flutter build apk --debug

Write-Host "APK: build\app\outputs\flutter-apk\app-debug.apk" -ForegroundColor Green
