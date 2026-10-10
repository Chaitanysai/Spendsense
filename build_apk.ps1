$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot'
$env:ANDROID_HOME = 'C:\Users\chait\AppData\Local\Android\Sdk'
$flutter = 'C:\shorebird-1.6.92\bin\cache\flutter\76ca3dff01cc7c5e6978e6b51e442777c6930419\bin\flutter.bat'

Write-Host "Stopping any running Gradle daemons..."
Set-Location android
& .\gradlew.bat --stop
Set-Location ..

Write-Host "Building APK release with JAVA_HOME=$env:JAVA_HOME"
& $flutter build apk --release
exit $LASTEXITCODE
