# Full capture matrix for SpendSense, light + dark, on a signed-in device.
#
#   .\tool\capture-all.ps1 -Serial bd5df849
#
# Requires an authenticated session: AuthGate blocks every screen behind
# Firebase sign-in, so this script never signs in and never touches credentials.
#
# Captures go through `screencap` + `adb pull`, never a PowerShell `>` redirect
# (redirection treats the bytes as text and mangles the PNG).
param(
    [string]$Serial = 'bd5df849',
    [string]$Out = 'screenshots2'
)

$ErrorActionPreference = 'Continue'
$adb = 'C:\Users\chait\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$env:ADB_VENDOR_KEYS = 'C:\Android\.android\adbkey'
$script:failures = @()

New-Item -ItemType Directory -Force $Out | Out-Null

function Shot([string]$name) {
    & $adb -s $Serial shell screencap -p /sdcard/s.png
    & $adb -s $Serial pull /sdcard/s.png "$Out\$name.png" 2>$null | Out-Null
    $f = Get-Item "$Out\$name.png" -ErrorAction SilentlyContinue
    if (-not $f) { Write-Host "MISSING  $name"; $script:failures += $name; return }
    $head = [System.IO.File]::ReadAllBytes($f.FullName)[0..7]
    if (-not ($head[0] -eq 0x89 -and $head[1] -eq 0x50)) {
        Write-Host "BAD PNG  $name ($($f.Length) bytes)"; $script:failures += $name; return
    }
    Write-Host ("captured {0,-34} {1,8} bytes" -f $name, $f.Length)
}

function Get-Ui {
    & $adb -s $Serial shell uiautomator dump /sdcard/ui.xml | Out-Null
    & $adb -s $Serial pull /sdcard/ui.xml "$Out\_ui.xml" 2>$null | Out-Null
    return Get-Content "$Out\_ui.xml" -Raw -ErrorAction SilentlyContinue
}

# Centre of the first node whose text or content-desc equals $label.
function Find-Node([string]$label) {
    $xml = Get-Ui
    if (-not $xml) { return $null }
    $pat = '(?:content-desc|text)="' + [regex]::Escape($label) + '"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
    $m = [regex]::Match($xml, $pat, 'IgnoreCase')
    if (-not $m.Success) { return $null }
    return @{
        X = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
        Y = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
    }
}

function Tap-Node([string]$label, [int]$settle = 2500) {
    $n = Find-Node $label
    if (-not $n) { Write-Host "NO NODE  '$label'"; $script:failures += "tap:$label"; return $false }
    & $adb -s $Serial shell input tap $n.X $n.Y
    Start-Sleep -Milliseconds $settle
    return $true
}

function Back([int]$settle = 2200) {
    & $adb -s $Serial shell input keyevent KEYCODE_BACK
    Start-Sleep -Milliseconds $settle
}

function Wake {
    & $adb -s $Serial shell input keyevent KEYCODE_WAKEUP | Out-Null
    & $adb -s $Serial shell wm dismiss-keyguard | Out-Null
    Start-Sleep -Milliseconds 700
}

function GoHome {
    & $adb -s $Serial shell am force-stop com.example.spendsense
    Start-Sleep -Milliseconds 600
    & $adb -s $Serial shell am start -n com.example.spendsense/.MainActivity | Out-Null
    Start-Sleep -Seconds 12
}

Wake
Write-Host "device: $(& $adb -s $Serial get-serialno)"
Write-Host "--- light ---"
GoHome
Shot '20-home-light'
Tap-Node 'Add expense' | Out-Null
Shot '21-add-expense-light'
Back

# Activity tab -> first row opens Transaction details (the Edit screen).
Tap-Node 'ACTIVITY' | Out-Null
Shot '22-activity-light'
