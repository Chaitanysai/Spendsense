$jdk17 = Get-ChildItem -Path 'C:\Program Files\Microsoft' -Filter 'jdk-17*' | Select-Object -First 1
if ($jdk17) {
    Write-Host "Found JDK 17 at: $($jdk17.FullName)"
    $env:JAVA_HOME = $jdk17.FullName
    Write-Host "JAVA_HOME set to: $env:JAVA_HOME"
    & "$env:JAVA_HOME\bin\java.exe" -version
} else {
    Write-Host "JDK 17 folder not found under C:\Program Files\Microsoft"
}
