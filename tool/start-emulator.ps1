# Starts the Boardhop Android emulator with working DNS.
#
# The AVD was created with:
#   sdkmanager --install "emulator" "platform-tools" "system-images;android-37.0;google_apis_playstore;x86_64"
#   avdmanager create avd --name boardhop_pixel_10_pro --package "system-images;android-37.0;google_apis_playstore;x86_64" --device pixel_10_pro
#
# -dns-server matters on Windows hosts whose first resolver is a VPN/virtual
# adapter: the emulator forwards guest DNS to it and name lookups time out,
# which shows up as a blank login.microsoftonline.com tab.

param(
    [string]$Avd = "boardhop_pixel_10_pro"
)

$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }
$emulator = Join-Path $sdk "emulator\emulator.exe"
if (-not (Test-Path $emulator)) { throw "Emulator not found at $emulator" }

& $emulator -avd $Avd -no-snapshot-load -no-boot-anim -netdelay none -netspeed full -dns-server 8.8.8.8,1.1.1.1
