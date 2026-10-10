$zip = 'C:\Users\chait\AppData\Local\Android\Sdk\cmdline-tools.zip'
$dest = 'C:\Users\chait\AppData\Local\Android\Sdk\cmdline-tools\temp'
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $dest)

$latest = 'C:\Users\chait\AppData\Local\Android\Sdk\cmdline-tools\latest'
if (Test-Path $latest) { Remove-Item -Recurse -Force $latest }
New-Item -ItemType Directory -Force $latest

$extractedDir = Join-Path $dest 'cmdline-tools'
if (Test-Path $extractedDir) {
    Move-Item -Force "$extractedDir\*" $latest
} else {
    Move-Item -Force "$dest\*" $latest
}
Remove-Item -Recurse -Force $dest
Remove-Item -Force $zip
Write-Host "Cmdline-tools successfully installed to latest"
