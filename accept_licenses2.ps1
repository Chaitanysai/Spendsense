$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:ANDROID_HOME = 'C:\Users\chait\AppData\Local\Android\Sdk'
$env:ANDROID_SDK_ROOT = 'C:\Users\chait\AppData\Local\Android\Sdk'
$flutter = 'C:\shorebird-1.6.92\bin\cache\flutter\76ca3dff01cc7c5e6978e6b51e442777c6930419\bin\flutter.bat'

$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = $flutter
$processInfo.Arguments = "doctor --android-licenses"
$processInfo.RedirectStandardInput = $true
$processInfo.UseShellExecute = $false
$process = [System.Diagnostics.Process]::Start($processInfo)
$sw = New-Object IO.StreamWriter $process.StandardInput
for($i=0; $i -lt 30; $i++) { $sw.WriteLine("y") }
$sw.Close()
$process.WaitForExit()
Write-Host "Licenses accepted successfully"
