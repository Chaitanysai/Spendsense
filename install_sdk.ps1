$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:ANDROID_HOME = 'C:\Users\chait\AppData\Local\Android\Sdk'
$env:ANDROID_SDK_ROOT = 'C:\Users\chait\AppData\Local\Android\Sdk'
$sdkmanager = 'C:\Users\chait\AppData\Local\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat'

# Accept licenses non-interactively
$yes = "$([char]10)$([char]10)$([char]10)$([char]10)$([char]10)$([char]10)$([char]10)"
$yes | & $sdkmanager --licenses --sdk_root="$env:ANDROID_HOME"

& $sdkmanager "platform-tools" "build-tools;34.0.0" "platforms;android-34" "platforms;android-33" --sdk_root="$env:ANDROID_HOME"
Write-Host "SDK components installed successfully"
