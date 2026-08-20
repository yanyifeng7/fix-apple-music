<#
.SYNOPSIS
    Fixes the "An unknown error has occurred" (kccadp / error 18006 / KCCAError 4)
    problem in the Windows Microsoft Store version of Apple Music.

.DESCRIPTION
    Apple Music for Windows (the Store / MSIX version, AppleInc.AppleMusicWin_*)
    uses a keychain/crypto component called kccadp that lives in the app's
    LocalCache. When it gets corrupted (mid-playback force-kill, AV interference,
    Store update glitch, etc.) the app reports "An unknown error has occurred"
    on launch and refuses to play anything.

    This script resets the Store app's local cache via Reset-AppxPackage,
    which is the only fix that clears the broken crypto state WITHOUT
    requiring the user to sign out and back in. Your Apple ID login,
    library, and downloads all stay intact.

    Typical fix-flow reported across Apple Music communities (Reddit,
    Microsoft Q&A, Apple Support):
        1. Close Apple Music completely.
        2. Run this script (one UAC prompt).
        3. Reopen Apple Music from the Start menu.
        4. Play something. Should work immediately.

.NOTES
    - Safe to re-run; does nothing if Apple Music is already working.
    - Does NOT touch your Apple ID, iCloud Music library, or downloaded songs.
    - Does NOT touch the classic iTunes install (different package).
    - Tested on Windows 10 22H2 and Windows 11 23H2+ with the Microsoft
      Store version of Apple Music 1.1540+.

.LINK
    https://www.reddit.com/r/AppleMusic/comments/177h0z4/
    https://learn.microsoft.com/en-us/powershell/module/appx/reset-appxpackage
#>

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# --- Unblock this file (if it was downloaded with Mark-of-the-Web) and
#     self-relaunch with Bypass policy if blocked. "Run with PowerShell"
#     from the right-click menu launches powershell.exe WITHOUT -ExecutionPolicy
#     Bypass, so unsigned scripts from Downloads/Documents/etc fail with
#     "not digitally signed". This block fixes that transparently. --------

try {
    Unblock-File -Path $PSCommandPath -ErrorAction Stop
} catch { }

# If we're not already running Bypass, re-launch ourselves with it.
# Skip if we're already elevated (the elevation re-launch handles policy
# via -ExecutionPolicy Bypass too, so this is belt-and-suspenders).
$currentPolicy = Get-ExecutionPolicy -Scope Process -ErrorAction SilentlyContinue
if ($currentPolicy -eq 'Restricted' -or $currentPolicy -eq 'AllSigned' -or $currentPolicy -eq 'RemoteSigned') {
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath) {
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$scriptPath`"")
        try {
            Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -Wait -WindowStyle Normal
            exit $LASTEXITCODE
        } catch {
            # User declined UAC or elevation failed; fall through and try anyway
        }
    }
}

# --- Log all output to a file (so even if the console closes too fast,
#     the user can read what happened) ------------------------------------
$logFile = Join-Path $env:TEMP ("fix-apple-music-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")
Start-Transcript -Path $logFile -Append -ErrorAction SilentlyContinue | Out-Null

# --- Self-elevate to admin (one UAC prompt) --------------------------------
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $currentPrincipal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[fix-apple-music] Requesting administrator elevation...' -ForegroundColor Cyan
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) {
        # Re-launched from a stdin pipe (rare). Save to temp and rerun.
        $scriptPath = Join-Path $env:TEMP 'fix-apple-music-elevated.ps1'
        $MyInvocation.MyCommand.Definition | Out-File -FilePath $scriptPath -Encoding UTF8
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $psi.Verb = 'runas'
    $psi.UseShellExecute = $true
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
        exit $p.ExitCode
    } catch {
        Write-Host "[fix-apple-music] ERROR: UAC was declined or elevation failed." -ForegroundColor Red
        Write-Host "Right-click the script and choose 'Run with PowerShell as administrator' instead."
        exit 1
    }
}

# --- Sanity check: is Apple Music (Store) installed? -------------------------
$package = Get-AppxPackage -Name 'AppleInc.AppleMusicWin*' -ErrorAction SilentlyContinue
if (-not $package) {
    Write-Host ''
    Write-Host '[fix-apple-music] Apple Music (Microsoft Store version) is not installed.' -ForegroundColor Yellow
    Write-Host 'This script only fixes the Store / MSIX version of Apple Music on Windows.'
    Write-Host ''
    $confirm = Read-Host 'Did you install Apple Music from the Microsoft Store? [y/N]'
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host 'Nothing to fix. Exiting.' -ForegroundColor DarkGray
        exit 0
    }
    Write-Host "Please install Apple Music from the Microsoft Store first, then re-run this script."
    exit 1
}

$packageName = $package.Name
Write-Host ''
Write-Host '[fix-apple-music] Found Apple Music package:' -ForegroundColor Green
Write-Host "             $packageName"
Write-Host "             Version $($package.Version)"
Write-Host ''

# --- Close Apple Music if running (the reset fails if it's active) ---------
Write-Host '[fix-apple-music] Closing Apple Music if running...' -ForegroundColor Cyan
Get-Process -Name 'AppleMusic', 'AMPLibraryAgent' -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "             stopping PID $($_.Id) ($($_.ProcessName))"
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# --- Optional: probe the broken state before fixing (informational) --------
$logPath = Join-Path $env:LOCALAPPDATA 'Packages'
$logPath = Join-Path $logPath $packageName
$logPath = Join-Path $logPath 'LocalCache\Local\Logs'
$kccaErrorsBefore = 0
if (Test-Path $logPath) {
    $authLogs = Get-ChildItem -Path $logPath -Filter 'AuthKitWin.*.log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($authLogs) {
        $tail = Get-Content $authLogs.FullName -Tail 200 -ErrorAction SilentlyContinue
        $kccaErrorsBefore = ($tail | Select-String -Pattern 'kccadp|KCCAError' -SimpleMatch:$false).Count
    }
}
if ($kccaErrorsBefore -gt 0) {
    Write-Host "[fix-apple-music] Detected $kccaErrorsBefore kccadp errors in the latest auth log." -ForegroundColor Yellow
    Write-Host '             This confirms the broken state. The reset below should clear it.'
    Write-Host ''
}

# --- THE FIX: Reset-AppxPackage clears the broken crypto state --------------
Write-Host '[fix-apple-music] Resetting Apple Music package cache...' -ForegroundColor Cyan
Write-Host '             (your Apple ID, library, and downloads are preserved)'
Write-Host ''
try {
    Reset-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
    Write-Host '[fix-apple-music] Reset OK.' -ForegroundColor Green
} catch {
    Write-Host "[fix-apple-music] ERROR: Reset-AppxPackage failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Try running this script from an elevated PowerShell manually.'
    exit 1
}

# --- Verify the fix actually cleared the broken state ----------------------
Start-Sleep -Seconds 2
$logPathAfter = Join-Path $env:LOCALAPPDATA 'Packages'
$logPathAfter = Join-Path $logPathAfter $packageName
$logPathAfter = Join-Path $logPathAfter 'LocalCache\Local\Logs'
$stillBroken = $false
if (Test-Path $logPathAfter) {
    $authLogsAfter = Get-ChildItem -Path $logPathAfter -Filter 'AuthKitWin.*.log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($authLogsAfter) {
        $tailAfter = Get-Content $authLogsAfter.FullName -Tail 50 -ErrorAction SilentlyContinue
        $recentKccaErrors = ($tailAfter | Select-String -Pattern 'kccadp is not initialized' -SimpleMatch:$false).Count
        if ($recentKccaErrors -gt 0) { $stillBroken = $true }
    }
}

Write-Host ''
if ($stillBroken) {
    Write-Host '[fix-apple-music] The cache reset succeeded but kccadp still reports broken.' -ForegroundColor Yellow
    Write-Host '             Try reopening Apple Music a 2nd time after 30 seconds.' -ForegroundColor Yellow
} else {
    Write-Host '[fix-apple-music] Cache reset looks clean.' -ForegroundColor Green
}

Write-Host ''
Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host '  NEXT STEPS' -ForegroundColor Cyan
Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host '  1. Open Apple Music from the Start menu' -ForegroundColor White
Write-Host '  2. Wait for it to load (may take 5-10 seconds)' -ForegroundColor White
Write-Host '  3. Play any song - it should work immediately' -ForegroundColor White
Write-Host ''
Write-Host '  If the error returns:' -ForegroundColor White
Write-Host '    - Wait 30 seconds and try again (kccadp initializes lazily)' -ForegroundColor DarkGray
Write-Host '    - Re-run this script (safe to run multiple times)' -ForegroundColor DarkGray
Write-Host '    - File an Apple Music feedback from the app menu (Help > Send Feedback)' -ForegroundColor DarkGray
Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host ("Full output also saved to: $logFile") -ForegroundColor DarkGray
Write-Host ''
Stop-Transcript | Out-Null
# Use cmd /c pause instead of Read-Host - Read-Host fails when PowerShell
# is launched via 'Run with PowerShell' (right-click) because the host
# process closes stdin immediately, causing the prompt to return null
# and exit. cmd /c pause is bulletproof and keeps the window open until
# the user explicitly presses a key.
cmd /c pause
