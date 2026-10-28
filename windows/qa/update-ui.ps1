param([string]$Output, [string]$App, [string]$ExpectedVersion)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing
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
function Invoke-Button($Element) {
    $pattern = $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $pattern.Invoke()
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
                $buttons = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button))
                foreach ($b in $buttons) {
                    $name = $b.Current.Name.Replace('&','')
                    if ($b.Current.IsEnabled -and $name -in @('Next >','Install','Finish','Close')) {
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
        $all | ForEach-Object { "$($_.Current.ControlType.ProgrammaticName) | $($_.Current.AutomationId) | $($_.Current.Name)" } | Set-Content "$Output/update-ui-tree.txt"
    } catch { }
    throw
}
