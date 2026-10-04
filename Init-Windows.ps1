[CmdletBinding()]
param (
    [Parameter()]
    [ValidateSet(1, 2)]
    [int]$Checkpoint = 1
)

# Unicode in PowerShell - https://stackoverflow.com/a/49481797
$PSDefaultParameterValues['*:Encoding'] = 'utf8'
$OutputEncoding = [System.Console]::OutputEncoding = [System.Console]::InputEncoding = [System.Text.Encoding]::UTF8

Import-Module -Force "$PSScriptRoot/home/Documents/PowerShell/Modules/Utils"
Import-Module -Force "$PSScriptRoot/home/Documents/PowerShell/Modules/Bitwarden"
Import-Module -Force "$PSScriptRoot/home/Documents/PowerShell/Helpers/Scoop"

if (Test-IsProcessElevated) {
    Write-Red 'Since typical Scoop installation is run from a non-admin PowerShell; this script cannot be executed from an elevated PowerShell session.'
    exit 1
}

if ($Checkpoint -eq 1) {

    if ($PSEdition -eq 'Core') {
        Write-Red 'Since Scoop uses PowerShell Core (pwsh.exe) internally, this script must be executed from Windows PowerShell (powershell.exe) so it can install/update the PowerShell Core.'
        exit 1
    }

    # https://github.com/ScoopInstaller/Scoop/wiki
    Write-Blue '# Install/update scoop'
    if (-not (Test-IsCommandAvailable 'scoop')) {
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        $FreshInstall = $true
    }
    else {
        if ((scoop config scoop_branch) -ne 'develop') {
            scoop config scoop_branch develop
        }
        scoop update
    }

    # https://aria2.github.io
    Write-Blue '# Install/update aria2'
    Install-ScoopPackage 'main/aria2'

    if (scoop config aria2-warning-enabled) {
        scoop config aria2-warning-enabled false
    }

    # https://www.7-zip.org
    Write-Blue '# Install/update 7zip'
    Install-ScoopPackage 'main/7zip'
    # reg import "$HOME/scoop/apps/7zip/current/install-context.reg"

    # https://innounp.sourceforge.net
    Write-Blue '# Install/update innounp'
    Install-ScoopPackage 'main/innounp'

    # https://github.com/activescott/lessmsi
    Write-Blue '# Install/update lessmsi'
    Install-ScoopPackage 'main/lessmsi'

    # https://wixtoolset.org
    Write-Blue '# Install/update dark'
    Install-ScoopPackage 'main/dark'

    # https://gitforwindows.org
    Write-Blue '# Install/update git'
    Install-ScoopPackage 'main/git'
    # reg import "$HOME/scoop/apps/git/current/install-context.reg"

    if ($null -ne $FreshInstall) {
        Write-Text 'Switching Scoop to develop branch...'
        if ((scoop config scoop_branch) -ne 'develop') {
            scoop config scoop_branch develop
        }
        scoop update
    }

    # https://microsoft.com/PowerShell
    Write-Blue '# Install/update PowerShell'
    Install-ScoopPackage 'main/pwsh'
    # reg import "$HOME/scoop/apps/pwsh/current/install-explorer-context.reg"
    # reg import "$HOME/scoop/apps/pwsh/current/install-file-context.reg"


    # https://github.com/bitwarden/clients
    Write-Blue '# Install/update Bitwarden CLI'
    Install-ScoopPackage 'main/bitwarden-cli'

    try {
        Write-Text 'Unlocking Bitwarden vault...'
        Unlock-Bitwarden

        # https://www.chezmoi.io
        Write-Blue '# Install/update chezmoi'
        Install-ScoopPackage 'main/chezmoi'

        Write-Text 'Applying chezmoi changes...'
        chezmoi git status *> $null
        if ($LASTEXITCODE -ne 0) {
            chezmoi init kumarchandresh --apply --force
        }
        else {
            chezmoi update --force
        }
        if ($LASTEXITCODE -eq 0) {
            Write-Green 'Done.'
        }
    }
    finally {
        Lock-Bitwarden
    }

    Write-Blue '# Install/ensure scoop buckets'
    $ScoopBuckets = @(
        [PSCustomObject]@{ Name = 'main' },
        [PSCustomObject]@{ Name = 'extras' },
        [PSCustomObject]@{ Name = 'versions' },
        [PSCustomObject]@{ Name = 'java' },
        [PSCustomObject]@{ Name = 'fonts'; Repo = 'https://github.com/kumarchandresh/scoop-fonts' }
    )
    
    if ("$(ssh -T git@github.com 2>&1)".Contains("You've successfully authenticated")) {
        $ScoopBuckets += [PSCustomObject]@{ Name = 'private'; Repo = 'git@github.com:kumarchandresh/scoop-private.git' }
    }
    $ScoopBuckets | ForEach-Object { $_ | Install-ScoopBucket }

    # https://github.com/microsoft/winget-cli/tree/master/src/PowerShell/Microsoft.WinGet.Client
    Write-Blue '# Install/update WinGet PowerShell Module'
    Install-ScoopPackage 'main/winget-ps'

    & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSCommandPath" -Checkpoint (++$Checkpoint)
    exit 0
}

Import-Module -Force 'Microsoft.WinGet.Client'
Import-Module -Force "$PSScriptRoot/home/Documents/PowerShell/Helpers/WinGet"

# https://github.com/microsoft/winget-cli
Write-Blue '# Install/update WinGet'
try {
    Assert-WinGetPackageManager -ErrorAction Stop
}
catch {
    Repair-WinGetPackageManager -Latest
}
Install-WinGetPackage -Id 'Microsoft.AppInstaller'

# https://code.visualstudio.com
Write-Blue '# Install/update Visual Studio Code'
Install-WinGetPackage 'Microsoft.VisualStudioCode' -Config 'Microsoft.VSCode.inf'

if (Test-IsBucketInstalled private) {
    # https://www.monolisa.dev
    Write-Blue '# Install/update font: MonoLisa'
    Install-ScoopPackage 'private/MonoLisa'
}
