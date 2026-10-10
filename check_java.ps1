$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot'
Write-Host "Environment JAVA_HOME: $env:JAVA_HOME"
Write-Host "Java version from JAVA_HOME:"
& "$env:JAVA_HOME\bin\java.exe" -version

Write-Host "Checking gradlew java detection:"
Set-Location android
& .\gradlew.bat --info
Set-Location ..
