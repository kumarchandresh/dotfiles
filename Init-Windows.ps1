[CmdletBinding()]
param (
    [switch]$SelfExecuted
)

# Configure UTF-8 encoding across console streams and pipeline operations
# https://stackoverflow.com/a/49481797
$PSDefaultParameterValues['*:Encoding'] = 'utf8'
$OutputEncoding = [System.Console]::OutputEncoding = [System.Console]::InputEncoding = [System.Text.Encoding]::UTF8

Import-Module -Force "$PSScriptRoot/home/Documents/PowerShell/Modules/Utils"
Import-Module -Force "$PSScriptRoot/home/Documents/PowerShell/Modules/Bitwarden"
Import-Module -Force "$PSScriptRoot/home/Documents/PowerShell/Modules/Scoop"
Import-Module -Force "$PSScriptRoot/home/Documents/PowerShell/Modules/WSL"

if ($PSEdition -eq 'Core') {
    Import-Module -Force 'Microsoft.WinGet.Client'
    Import-Module -Force "$PSScriptRoot/home/Documents/PowerShell/Modules/WinGet"
}

if ((Test-ProcessElevated) -and (-not $SelfExecuted)) {
    Write-Red 'Cannot be executed from an elevated PowerShell session.'
    exit 1
}

if (($PSEdition -eq 'Core') -and (-not $SelfExecuted)) {
    Write-Red 'Must be executed from Windows PowerShell (powershell.exe) so Scoop can install or update PowerShell Core (pwsh.exe).'
    exit 1
}

Restore-EnvPath

#region Phase 1
# ---------------------------------------------------------------------------
# Bootstrap Scoop and PowerShell Core
#
# Bootstrap Scoop in user-space without elevation to acquire Git, PowerShell Core,
# gsudo, winget-ps, chezmoi, and bitwarden-cli in a single batched operation.
# Use Windows PowerShell 5.1 strictly as the temporary launchpad.
# ---------------------------------------------------------------------------
if ($PSEdition -ne 'Core') {

    Write-Title ':: Bootstrap Scoop and PowerShell Core'
    if (-not (Test-CommandAvailable scoop)) {
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    }
    else {
        scoop update
    }

    if ((scoop config scoop_branch) -ne 'develop') {
        scoop config scoop_branch develop
    }

    if ((scoop config aria2-warning-enabled) -ne $false) {
        scoop config aria2-warning-enabled false
    }

    @(
        'main/aria2'
        'main/7zip'
        'main/innounp'
        'main/lessmsi'
        'main/dark'
        'main/git'
        'main/pwsh'
        'main/gsudo'
        'main/winget-ps'
        'main/chezmoi'
        'main/bitwarden-cli'
        'main/starship'
    ) | Install-ScoopPackage

    # Re-launch in PowerShell Core to continue execution
    & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSCommandPath" -SelfExecuted
    exit $LASTEXITCODE
}
#endregion

#region Phase 2
# ---------------------------------------------------------------------------
# Install System Dependencies (Elevated)
#
# Ensure WinGet availability, then elevate once via gsudo to install
# machine-level dependencies in a separate elevated process. Verify pending
# reboot requirements and install the default WSL distribution.
# ---------------------------------------------------------------------------
if (-not (Test-ProcessElevated)) {

    Write-Title ':: Install System Dependencies'
    try {
        Assert-WinGetPackageManager -Latest -ErrorAction Stop
    }
    catch {
        Repair-WinGetPackageManager -Latest -Force
    }

    Write-Yellow '! Running as administrator; expect a UAC prompt...'
    & gsudo --integrity High pwsh -NoProfile -ExecutionPolicy (Get-ExecutionPolicy) -File $PSCommandPath -SelfExecuted
    $gsudoExitCode = $LASTEXITCODE

    if ($gsudoExitCode -notin @(0, 3010)) {
        Write-Red 'Elevated system setup failed.'
        exit 1
    }

    Restore-EnvPath

    if ($gsudoExitCode -eq 3010) {
        Write-Yellow '! A system restart is required to activate Windows Subsystem for Linux before continuing.'
        $restart = Read-Host 'Restart computer now (y/N)? '
        if ($restart -eq 'y') {
            Restart-Computer
        }
        exit 0
    }

    if (Test-WslAvailable) {
        @(
            'archlinux'
        ) | Install-WslDistro
    }
}
else {

    @(
        'Microsoft.VCRedist.2015+.x64'
        'Microsoft.VCRedist.2015+.x86'
    ) | Install-WinGetPackage -Global

    $pendingReboot = $false

    @(
        'Microsoft-Windows-Subsystem-Linux'
        'VirtualMachinePlatform'
        'HypervisorPlatform'
    ) | ForEach-Object {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $_
        if ($feature.State -notin @('Enabled', 'EnablePending')) {
            Write-Green "+ WindowsOptionalFeature/$_"
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $_ -All -NoRestart
            if ($result.RestartNeeded) {
                $script:pendingReboot = $true
            }
        }
        else {
            Write-Muted "~ WindowsOptionalFeature/$_"
            if ($feature.State -eq 'EnablePending') {
                $script:pendingReboot = $true
            }
        }
    }

    if (-not (Test-WslAvailable)) {
        Update-Wsl
    }

    if ($pendingReboot) {
        exit 3010
    }

    exit 0
}
#endregion

#region Phase 3
# ---------------------------------------------------------------------------
# Apply Dotfiles and Secrets
#
# Unlock Bitwarden to decrypt secrets and apply Chezmoi dotfiles.
# Applies personal configuration files and GitHub SSH keys required before
# cloning private repositories.
# ---------------------------------------------------------------------------

Write-Title ':: Apply Dotfiles and Secrets'

$bwStatus = Unlock-Bitwarden
if ($bwStatus -eq 'Failed') {
    Write-Red 'Bitwarden vault is locked; cannot apply dotfiles.'
    exit 1
}

try {
    chezmoi git status *> $null
    if ($LASTEXITCODE -ne 0) {
        chezmoi init kumarchandresh --apply --force
    }
    else {
        chezmoi update --force
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Red 'Chezmoi failed to apply dotfiles.'
        exit 1
    }
}
finally {
    if ($bwStatus -eq 'Unlocked') {
        Lock-Bitwarden
    }
}
#endregion

#region Phase 4
# ---------------------------------------------------------------------------
# Install Remaining Packages
#
# Add extra Scoop buckets (including private buckets authenticated via SSH),
# then install remaining user packages.
# ---------------------------------------------------------------------------
Write-Title ':: Install Remaining Packages'

$ScoopBuckets = @(
    [PSCustomObject]@{ Name = 'main' },
    [PSCustomObject]@{ Name = 'extras' },
    [PSCustomObject]@{ Name = 'versions' },
    [PSCustomObject]@{ Name = 'java' },
    [PSCustomObject]@{ Name = 'fonts'; Repo = 'https://github.com/kumarchandresh/scoop-fonts' }
)

if ("$(ssh -T -o StrictHostKeyChecking=accept-new git@github.com 2>&1)".Contains("You've successfully authenticated")) {
    $ScoopBuckets += [PSCustomObject]@{ Name = 'private'; Repo = 'git@github.com:kumarchandresh/scoop-private.git' }
}
$ScoopBuckets | Install-ScoopBucket

@(
    'Microsoft.VisualStudioCode'
) | Install-WinGetPackage

@(
    # Command-line utilities
    'main/microsoft-coreutils'
    'main/sed'
    'main/gawk'
    'main/less'
    'main/fastfetch'
    'main/fd'
    'main/fzf'
    'main/ripgrep'
    'main/zoxide'
    'main/bat'
    'main/delta'
    'main/tlrc'
    'extras/terminal-icons'
    'fonts/SymbolsNerdFont'
) | Install-ScoopPackage

if (Test-ScoopBucketInstalled private) {
    @(
        'private/MonoLisa'
    ) | Install-ScoopPackage
}
#endregion
