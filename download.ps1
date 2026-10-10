$url = 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip'
$out = 'C:\Users\chait\AppData\Local\Android\Sdk\cmdline-tools.zip'
if (Test-Path $out) { Remove-Item $out }
Import-Module BitsTransfer
Start-BitsTransfer -Source $url -Destination $out
Write-Host "BitsTransfer completed"
