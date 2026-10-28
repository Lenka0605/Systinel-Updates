param([bool]$PublicFeed = $false)
$ErrorActionPreference = 'Stop'
$output = Join-Path $PWD 'qa-output'
$setup = (Get-ChildItem "$output/*windows-x64-Setup.exe" | Select-Object -First 1).FullName
$appDir = Join-Path $env:LOCALAPPDATA 'Programs/Systinel'
$app = Join-Path $appDir 'Systinel.exe'
$prefsDir = Join-Path $env:LOCALAPPDATA 'Systinel'
$prefs = Join-Path $prefsDir 'preferences.json'
function Run-Checked([string]$File, [string[]]$Arguments, [int]$Seconds = 120) {
    $p = Start-Process -FilePath $File -ArgumentList $Arguments -PassThru
    if (!$p.WaitForExit($Seconds * 1000)) { throw "Process exceeded timeout: $File" }
    if ($p.ExitCode -ne 0) { throw "Process failed: $File (exit $($p.ExitCode))" }
}
try {
    $crossVersion = $false
    if ($PublicFeed) {
        $baseline = (Get-ChildItem 'qa-baseline/*windows-x64-Setup.exe' | Select-Object -First 1).FullName
        Run-Checked $baseline @('/S')
        New-Item -ItemType Directory -Force $prefsDir | Out-Null
        Set-Content -Path $prefs -Value '{"Schema":1,"Language":"en","Theme":"light","Mode":0,"CloseToTray":false,"AutoCheckUpdates":false,"BackgroundApps":[]}' -NoNewline
        & "$PSScriptRoot/update-ui.ps1" -Output $output -App $app -ExpectedVersion '1.9.0.75'
        if (!(Test-Path "$output/settings-update.json")) { throw 'Cross-version settings update unconfirmed' }
        $preserved = Get-Content $prefs -Raw | ConvertFrom-Json
        if ($preserved.Language -ne 'en' -or $preserved.Mode -ne 0 -or $preserved.Theme -ne 'light') { throw 'Cross-version upgrade lost preferences' }
        $crossVersion = $true
    }
    Run-Checked $setup @('/S')
    if (!(Test-Path $app)) { throw 'Installation missing executable' }
    if (!(Test-Path "$env:APPDATA/Microsoft/Windows/Start Menu/Programs/Systinel/Systinel.lnk")) { throw 'Start Menu shortcut missing' }
    if (!(Test-Path "$env:USERPROFILE/Desktop/Systinel.lnk") -and !(Test-Path "$([Environment]::GetFolderPath('Desktop'))/Systinel.lnk")) { throw 'Desktop shortcut missing' }
    $nativeMode = if ($PublicFeed) { '--self-test' } else { '--native-test' }
    Run-Checked $app @($nativeMode, "`"$output/native.json`"") 300
    $native = Get-Content "$output/native.json" -Raw | ConvertFrom-Json
    if (!$native.ok) { throw 'Native checks failed' }
    Run-Checked "$appDir/fan-host/SystinelFanHost.exe" @('--probe', "`"$output/hardware-readonly.json`"") 120
    New-Item -ItemType Directory -Force $prefsDir | Out-Null
    $sentinel = '{"Schema":1,"Language":"de","Theme":"light","Mode":0,"CloseToTray":false,"AutoCheckUpdates":false,"BackgroundApps":[]}'
    Set-Content -Path $prefs -Value $sentinel -NoNewline
    $before = (Get-FileHash $prefs).Hash
    # Run the app, then let the installer request a graceful shutdown and replace the existing build.
    $running = Start-Process $app -PassThru
    Start-Sleep -Seconds 5
    if ($running.HasExited) { throw 'App exited unexpectedly' }
    $installer = if ($PublicFeed) { $native.downloadedInstaller } else { $setup }
    Run-Checked $installer @('/S')
    if (!$running.WaitForExit(30000)) { throw 'Installer did not gracefully close the app' }
    $restored = Get-Content $prefs -Raw | ConvertFrom-Json
    if ($restored.Language -ne 'de' -or $restored.Mode -ne 0 -or $restored.Theme -ne 'light') { throw 'Upgrade lost preferences' }
    $ui = Join-Path $output 'ui'
    if (!(Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer; Start-Sleep -Seconds 3 }
    Run-Checked $app @('--qa', "`"$ui`"", '--tray-qa')
    if (!(Test-Path "$ui/ui-complete.json")) { throw 'UI capture incomplete' }
    if ((Get-ChildItem "$ui/*.png").Count -lt 6) { throw 'UI screenshots missing' }
    if (!(Test-Path "$ui/tray.json") -or !(Get-Content "$ui/tray.json" -Raw | ConvertFrom-Json).ok) { throw 'Native tray verification missing' }
    $installedVersion = (Get-Item $app).VersionInfo.FileVersion
    # Uninstaller copies itself to temp by default; /_?= suppresses that fork so we can await it.
    Run-Checked "$appDir/Uninstall.exe" @('/S', "_?=$appDir")
    if (Test-Path "$appDir/Systinel.exe") { throw 'Uninstall left application binaries' }
    if (Test-Path 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/Systinel') { throw 'Uninstall registry entry remains' }
    if (!(Test-Path $prefs)) { throw 'Uninstall unexpectedly deleted preferences' }
    @{ok=$true; installerSha256=(Get-FileHash $setup -Algorithm SHA256).Hash.ToLowerInvariant(); installedVersion=$installedVersion; publicFeed=$PublicFeed; settingsCrossVersionUpdate=$crossVersion; nativeTray=$true; install=$true; native=$true; gracefulUpdate=$true; preferencesPreserved=$true; ui=$true; uninstall=$true; os=[Environment]::OSVersion.VersionString} | ConvertTo-Json | Set-Content "$output/result.json"
} catch {
    $_ | Out-String | Set-Content "$output/error.txt"
    if (Test-Path "$prefsDir/app.log") { Copy-Item "$prefsDir/app.log" "$output/app-log.txt" }
    throw
}
