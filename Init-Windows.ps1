[CmdletBinding()]
param (
    [switch]$SelfExecuted
)

# Configure UTF-8 encoding across console streams and pipeline operations
$PSDefaultParameterValues['*:Encoding'] = 'utf8'
$OutputEncoding = [System.Console]::OutputEncoding = [System.Console]::InputEncoding = [System.Text.Encoding]::UTF8

Import-Module -Force "$PSScriptRoot/home/Documents/PowerShell/Modules/Utils"
Import-Module -Force "$PSScriptRoot/home/Documents/PowerShell/Modules/Scoop"

if ($PSEdition -eq 'Core') {
    Import-Module -Force 'Microsoft.WinGet.Client'
    Import-Module -Force "$PSScriptRoot/home/Documents/PowerShell/Modules/WinGet"
    Import-Module -Force "$PSScriptRoot/home/Documents/PowerShell/Modules/Bitwarden"
}

if ((Test-IsProcessElevated) -and (-not $SelfExecuted)) {
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
# Bootstrap Scoop, PowerShell Core, and Core CLI Tools
#
# Bootstrap Scoop in user-space without elevation to acquire Git, PowerShell Core,
# gsudo, winget-ps, chezmoi, and bitwarden-cli in a single batched operation.
# Use Windows PowerShell 5.1 strictly as the temporary launchpad.
# ---------------------------------------------------------------------------
if ($PSEdition -ne 'Core') {

    Write-Title ':: Bootstrap Scoop, PowerShell Core, and Core CLI Tools'
    if (-not (Test-IsCommandAvailable 'scoop')) {
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    }
    else {
        if (Test-IsCommandAvailable 'git') {
            scoop update
        }
        else {
            Write-Yellow 'git is not available in PATH; skipping scoop update'
        }
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
        'main/pwsh'
        'main/gsudo'
        'main/winget-ps'
        'main/chezmoi'
        'main/bitwarden-cli'
    ) | Install-ScoopPackage

    # Re-launch in PowerShell Core to continue execution
    & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSCommandPath" -SelfExecuted
    exit $LASTEXITCODE
}
#endregion

#region Phase 2
# ---------------------------------------------------------------------------
# Provision System Dependencies (Elevated)
#
# Ensure WinGet availability, then elevate once via gsudo to install
# machine-level dependencies in a separate elevated process.
# ---------------------------------------------------------------------------
if (-not (Test-IsProcessElevated)) {

    Write-Title ':: Provision System Dependencies'
    try {
        Assert-WinGetPackageManager -Latest -ErrorAction Stop
    }
    catch {
        Repair-WinGetPackageManager -Latest -Force
    }

    Write-Yellow 'Running as administrator; expect a UAC prompt...'
    & gsudo --integrity High pwsh -NoProfile -ExecutionPolicy (Get-ExecutionPolicy) -File $PSCommandPath -SelfExecuted
    if ($LASTEXITCODE -ne 0) {
        Write-Red 'Elevated system setup failed.'
        exit 1
    }

    Restore-EnvPath
}
else {

    @(
        'Microsoft.VCRedist.2015+.x64'
        'Microsoft.VCRedist.2015+.x86'
        'Git.Git'
    ) | Install-WinGetPackage -Global

    exit 0
}
#endregion

#region Phase 3
# ---------------------------------------------------------------------------
# Deploy Dotfiles and Secrets (Chezmoi & Bitwarden)
#
# Unlock Bitwarden to decrypt secrets and apply Chezmoi dotfiles.
# Deploys personal configuration files and GitHub SSH keys required before
# cloning private repositories. Git is guaranteed in PATH from Phase 1.
# ---------------------------------------------------------------------------
if (-not (Test-IsCommandAvailable 'git')) {
    Write-Red 'git is not available in PATH; ensure Scoop bootstrap completed successfully.'
    exit 1
}

Write-Title ':: Deploy Dotfiles and Secrets (Chezmoi & Bitwarden)'

try {
    Unlock-Bitwarden

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
    Lock-Bitwarden
}
#endregion

#region Phase 4
# ---------------------------------------------------------------------------
# Extend Package Sources and Install User Applications
#
# Complete bootstrapping. Leverage GitHub SSH keys deployed by Chezmoi to clone
# the private Scoop bucket without credential friction. Configure all extended
# buckets and install remaining user-space applications and fonts.
# ---------------------------------------------------------------------------
Write-Title ':: Extend Package Sources and Install User Applications'

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

if (Test-IsScoopBucketInstalled private) {
    @(
        'private/MonoLisa'
    ) | Install-ScoopPackage
}
#endregion
