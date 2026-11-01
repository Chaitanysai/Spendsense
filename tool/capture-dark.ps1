# Capture the dark scheme by driving the app's own Appearance screen.
#
# Dark cannot be reached with `adb shell cmd uimode night yes`: ThemeProvider
# persists an explicit ThemeMode.light/dark/system, and the default is Light,
# so the OS setting is ignored. The app's toggle is the only honest path.
param(
    [string]$Serial = 'emulator-5554',
    [string]$Out = 'screenshots2'
)

$adb = 'C:\Users\chait\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$env:ADB_VENDOR_KEYS = 'C:\Android\.android\adbkey'
New-Item -ItemType Directory -Force $Out | Out-Null

function Tap-Node([string]$label) {
    & $adb -s $Serial shell uiautomator dump /sdcard/ui.xml | Out-Null
    & $adb -s $Serial pull /sdcard/ui.xml "$Out\_ui.xml" 2>$null | Out-Null
    $xml = Get-Content "$Out\_ui.xml" -Raw
    $pat = '(?:content-desc|text)="' + [regex]::Escape($label) + '"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
    $m = [regex]::Match($xml, $pat, 'IgnoreCase')
    if (-not $m.Success) {
        Write-Host "MISS: '$label' not on screen; visible nodes:"
        $py = 'C:\Users\chait\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
        & $py 'C:\Users\chait\AppData\Local\Temp\opencode\ui_nodes.py' "$Out\_ui.xml" | Select-Object -First 15
        throw "no node '$label'"
    }
    $x = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
    $y = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
    Write-Host ("tap '{0}' at ({1},{2})" -f $label, $x, $y)
    & $adb -s $Serial shell input tap $x $y
    Start-Sleep -Milliseconds 2500
}

function Shot([string]$name) {
    & $adb -s $Serial shell screencap -p /sdcard/s.png
    & $adb -s $Serial pull /sdcard/s.png "$Out\$name.png" 2>$null | Out-Null
    $f = Get-Item "$Out\$name.png"
    Write-Host ("captured {0,-28} {1,9} bytes" -f $name, $f.Length)
    return $f.Length
}

& $adb -s $Serial shell am start -n com.example.spendsense/.MainActivity | Out-Null
Start-Sleep -Seconds 13

Tap-Node 'SETTINGS'
Tap-Node 'Appearance'
$before = Shot '17-appearance-light-check'
Tap-Node 'Dark'
$after = Shot '18-appearance-dark'
if ($before -eq $after) { throw 'Dark tap did not change the screen' }

Tap-Node 'Arrow back'
Shot '19-settings-dark'
Tap-Node 'HOME'
Shot '20-home-dark'
Write-Host 'done'
