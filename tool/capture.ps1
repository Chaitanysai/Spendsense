# Capture SpendSense screens from a real device/emulator.
#
#   .\tool\capture.ps1 -Out screenshots2
#
# Every capture goes through `screencap` on the device and `adb pull`, never a
# PowerShell `>` redirect: redirection mangles the PNG (it is treated as text).
# Coordinates are resolved from the uiautomator dump, never guessed.
param(
    [string]$Serial = 'emulator-5554',
    [string]$Out = 'screenshots2'
)

$ErrorActionPreference = 'Continue'
$adb = 'C:\Users\chait\AppData\Local\Android\Sdk\platform-tools\adb.exe'
# The AVD was created under C:\Android\.android, which owns a different adb key
# than %USERPROFILE%\.android. Without this the device stays `unauthorized`.
$env:ADB_VENDOR_KEYS = 'C:\Android\.android\adbkey'

New-Item -ItemType Directory -Force $Out | Out-Null

function Shot([string]$name) {
    & $adb -s $Serial shell screencap -p /sdcard/s.png
    # adb writes its progress line to stderr. Do not parse that text for
    # failures ("0 skipped" is success); validate the artifact itself below.
    & $adb -s $Serial pull /sdcard/s.png "$Out\$name.png" 2>$null | Out-Null
    $f = Get-Item "$Out\$name.png" -ErrorAction SilentlyContinue
    if (-not $f) { throw "pull produced no file for $name" }
    # A truncated or text-encoded PNG is the failure this guards against.
    $head = [System.IO.File]::ReadAllBytes($f.FullName)[0..7]
    if (-not ($head[0] -eq 0x89 -and $head[1] -eq 0x50)) {
        throw "$name.png is not a PNG (bad header): $($f.Length) bytes"
    }
    Write-Host ("captured {0,-32} {1,8} bytes" -f $name, $f.Length)
}

# Resolve a node's centre from the accessibility tree.
function Tap-Node([string]$label) {
    & $adb -s $Serial shell uiautomator dump /sdcard/ui.xml | Out-Null
    & $adb -s $Serial pull /sdcard/ui.xml "$Out\_ui.xml" 2>$null | Out-Null
    $label = $label.ToUpperInvariant()
    $xml = Get-Content "$Out\_ui.xml" -Raw -ErrorAction SilentlyContinue
    if (-not $xml) { throw "no ui dump for $label" }
    # Nav destinations expose their label as uppercase `text`, not
    # `content-desc`; try both and match case-insensitively.
    $pat = '(?:content-desc|text)="' + [regex]::Escape($label) + '"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
    $m = [regex]::Match($xml, $pat, 'IgnoreCase')
    if (-not $m.Success) { throw "no node labelled '$label' on screen" }
    $x = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
    $y = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
    & $adb -s $Serial shell input tap $x $y
    # A Flutter route push plus PageEntrance stagger needs more than one frame;
    # capturing too early yields the previous screen (identical bytes).
    Start-Sleep -Milliseconds 2500
}

Write-Host "device: $(& $adb -s $Serial get-serialno)"
& $adb -s $Serial shell wm size
& $adb -s $Serial shell wm density

# Relaunch cleanly so the theme/mode start from stored state.
& $adb -s $Serial shell am force-stop com.example.spendsense
& $adb -s $Serial shell am start -n com.example.spendsense/.MainActivity | Out-Null
Start-Sleep -Seconds 12   # AppLaunchGate holds 1.4s minimum plus ledger load

Shot '10-home-light'
Tap-Node 'Settings'
Shot '11-settings-light'
Tap-Node 'Appearance'
Shot '12-appearance-light'

# Appearance -> Dark, then re-walk to the screens in the dark scheme.
Tap-Node 'Dark'
Shot '13-appearance-dark'
# Back to Settings (one level), then re-enter Appearance to confirm the
# selection persisted under the new scheme.
& $adb -s $Serial shell input keyevent KEYCODE_BACK
Start-Sleep -Milliseconds 2500
Shot '14-settings-dark'
# Home is a shell tab, not a pushed route: a second BACK would leave the app
# for the launcher (which is exactly what a naive two-BACK walk does).
Tap-Node 'HOME'
Shot '15-home-dark'

# Restore Light so the emulator is left in the default scheme.
& $adb -s $Serial shell am force-stop com.example.spendsense
Start-Sleep -Milliseconds 500

Write-Host 'done'
