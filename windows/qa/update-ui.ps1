param([string]$Output, [string]$App, [string]$ExpectedVersion)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class SystinelQaNative {
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr window, StringBuilder text, int size);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr window, uint message, IntPtr w, IntPtr l);
}
'@
function Wait-Element([System.Windows.Automation.AutomationElement]$Root, [System.Windows.Automation.AutomationProperty]$Property, [string]$Value, [int]$Seconds = 40) {
    $condition = [System.Windows.Automation.PropertyCondition]::new($Property, $Value)
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        $e = $Root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
        if ($null -ne $e) { return $e }
        Start-Sleep -Milliseconds 400
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "UI element missing: $Value"
}
function Is-NativeButton($Element) {
    $handle = [IntPtr]$Element.Current.NativeWindowHandle
    if ($handle -eq [IntPtr]::Zero) { return $false }
    $class = [System.Text.StringBuilder]::new(256)
    [void][SystinelQaNative]::GetClassName($handle, $class, $class.Capacity)
    return $class.ToString() -eq 'Button'
}
function Invoke-Button($Element) {
    $pattern = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        $pattern.Invoke()
    } elseif (Is-NativeButton $Element) {
        # NSIS's language plugin exposes its Win32 buttons as UIA panes, without Invoke.
        # BM_CLICK acts on that exact button; no global keystrokes or process termination.
        if (![SystinelQaNative]::PostMessage([IntPtr]$Element.Current.NativeWindowHandle, 0xF5, [IntPtr]::Zero, [IntPtr]::Zero)) { throw 'NSIS button click failed' }
    } else { throw "Unsupported button: $($Element.Current.Name), class=$($Element.Current.ClassName)" }
}
function Capture-Desktop([string]$Path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = [System.Drawing.Bitmap]::new($b.Width, $b.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size); $bmp.Save($Path) } finally { $g.Dispose(); $bmp.Dispose() }
}
$p = Start-Process $App -PassThru
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do { $p.Refresh(); if ($p.MainWindowHandle -ne 0) { break }; Start-Sleep -Milliseconds 300 } while ([DateTime]::UtcNow -lt $deadline)
    if ($p.MainWindowHandle -eq 0) { throw 'Baseline UI did not open' }
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
    $nav = Wait-Element $root ([System.Windows.Automation.AutomationElement]::AutomationIdProperty) 'nav-settings'
    Invoke-Button $nav
    Invoke-Button (Wait-Element $root ([System.Windows.Automation.AutomationElement]::NameProperty) 'Check for Updates')
    $download = Wait-Element $root ([System.Windows.Automation.AutomationElement]::NameProperty) 'Download update' 60
    Capture-Desktop "$Output/update-available.png"
    Invoke-Button $download
    $install = Wait-Element $root ([System.Windows.Automation.AutomationElement]::NameProperty) 'Install update' 180
    Capture-Desktop "$Output/update-verified.png"
    Invoke-Button $install
    if (!$p.WaitForExit(30000)) { throw 'Install Update did not gracefully exit old app' }
    # The old production app launches its verified installer without developer flags.
    # Complete that normal NSIS wizard via its own accessible buttons.
    $desktop = [System.Windows.Automation.AutomationElement]::RootElement
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    $finished = $false
    do {
        $windows = $desktop.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($w in $windows) {
            $title = $w.Current.Name
            if ($title -eq 'Installer Language') {
                Invoke-Button (Wait-Element $w ([System.Windows.Automation.AutomationElement]::NameProperty) 'OK' 3)
            } elseif ($title -like 'Systinel*Windows Preview*' -or $title -like 'Systinel*Setup*') {
                $buttons = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
                foreach ($b in $buttons) {
                    $name = $b.Current.Name.Replace('&','')
                    if ($b.Current.IsEnabled -and $name -in @('Next >','Install','Finish','Close') -and (Is-NativeButton $b)) {
                        if ($name -in @('Finish','Close')) { Capture-Desktop "$Output/update-installed.png"; $finished = $true }
                        Invoke-Button $b
                        break
                    }
                }
            }
        }
        if ($finished) { break }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    if (!$finished) { Capture-Desktop "$Output/update-installer-timeout.png"; throw 'Update wizard did not finish' }
    if ((Get-Item $App).VersionInfo.FileVersion -ne $ExpectedVersion) { throw 'Settings update installed wrong version' }
    # The Finish page may open the new app: request a graceful exit through its supported endpoint.
    Start-Sleep -Seconds 3
    $exit = Start-Process $App -ArgumentList '--prepare-update' -PassThru
    if (!$exit.WaitForExit(30000) -or $exit.ExitCode -ne 0) { throw 'Updated app did not exit normally' }
    @{ok=$true; baseline='1.8.0.74'; installedVersion=$ExpectedVersion; settingsCheck=$true; settingsDownload=$true; signatureAndHashVerified=$true; settingsInstall=$true; standardWizard=$true} | ConvertTo-Json | Set-Content "$Output/settings-update.json"
} catch {
    Capture-Desktop "$Output/update-error.png"
    try {
        $all = [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        $all | ForEach-Object { "$($_.Current.ControlType.ProgrammaticName) | $($_.Current.ClassName) | $($_.Current.NativeWindowHandle) | $($_.Current.AutomationId) | $($_.Current.Name)" } | Set-Content "$Output/update-ui-tree.txt"
    } catch { }
    throw
}
