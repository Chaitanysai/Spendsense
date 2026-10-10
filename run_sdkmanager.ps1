$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:ANDROID_HOME = 'C:\Users\chait\AppData\Local\Android\Sdk'
$sdkmanager = "$env:ANDROID_HOME\cmdline-tools\latest\bin\sdkmanager.bat"

$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName = $sdkmanager
$pinfo.Arguments = '--licenses'
$pinfo.RedirectStandardInput = $true
$pinfo.RedirectStandardOutput = $true
$pinfo.RedirectStandardError = $true
$pinfo.UseShellExecute = $false
$p = [System.Diagnostics.Process]::Start($pinfo)
$writer = $p.StandardInput
for ($i = 0; $i -lt 100; $i++) {
    $writer.WriteLine('y')
}
$writer.Close()
$p.WaitForExit(15000)
Write-Host "Exit code: $($p.ExitCode)"
Write-Host "Output:"
Write-Host $p.StandardOutput.ReadToEnd()
Write-Host "Error:"
Write-Host $p.StandardError.ReadToEnd()
