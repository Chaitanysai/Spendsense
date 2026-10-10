$zip = 'C:\Users\chait\AppData\Local\Android\Sdk\cmdline-tools.zip'
$dest = 'C:\Users\chait\AppData\Local\Android\Sdk\cmdline-tools\temp'
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $dest)
Write-Host "Extracted successfully"
