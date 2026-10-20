function Test-ProcessElevated {
    [CmdletBinding()]
    [OutputType([bool])]
    param ()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restore-EnvPath {
    [CmdletBinding()]
    param ()

    # https://superuser.com/q/867728/1042970
    # Windows is crazy; it prepends system path to user path; which results in
    # system applications taking precedence over user applications.
    ${env:Path} = @(
        [Environment]::GetEnvironmentVariable('Path', 'User')
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
    ) -join ';'
}

function Write-Title {
    Write-Host ''
    Write-Host @args -ForegroundColor Cyan
}

function Write-Blue { Write-Host @args -ForegroundColor Blue }
function Write-Cyan { Write-Host @args -ForegroundColor Cyan }
function Write-Text { Write-Host @args -ForegroundColor Gray }
function Write-Green { Write-Host @args -ForegroundColor Green }
function Write-Magenta { Write-Host @args -ForegroundColor Magenta }
function Write-Red { Write-Host @args -ForegroundColor Red }
function Write-White { Write-Host @args -ForegroundColor White }
function Write-Yellow { Write-Host @args -ForegroundColor Yellow }
function Write-DarkBlue { Write-Host @args -ForegroundColor DarkBlue }
function Write-DarkCyan { Write-Host @args -ForegroundColor DarkCyan }
function Write-Muted { Write-Host @args -ForegroundColor DarkGray }
function Write-DarkGreen { Write-Host @args -ForegroundColor DarkGreen }
function Write-DarkMagenta { Write-Host @args -ForegroundColor DarkMagenta }
function Write-DarkRed { Write-Host @args -ForegroundColor DarkRed }
function Write-DarkYellow { Write-Host @args -ForegroundColor DarkYellow }

function Test-CommandAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string]$Command
    )

    return [bool](Get-Command -Name $Command -ErrorAction SilentlyContinue)
}

function Test-WslAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param ()

    if (-not (Test-CommandAvailable wsl)) {
        return $false
    }

    $status = (wsl --status 2>&1 | Out-String) -replace "`0", ''
    return [bool]($status -match 'Default Version:\s+[12]')
}

# https://stackoverflow.com/a/47869761
# https://stackoverflow.com/a/68627581
function Test-RebootPending {
    [CmdletBinding()]
    [OutputType([bool])]
    param ()

    # 1. Component Based Servicing (CBS)
    $cbsPending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending')

    # 2. Windows Update & Update Orchestrator
    $wuauPending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $orchPending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\RebootRequired'
    $windowsUpdate = $wuauPending -or $orchPending

    # 3. Windows Installer (MSI) InProgress
    $msiPending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\InProgress'

    # 4. Computer Rename Pending
    $actComp = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name 'ComputerName' -ErrorAction SilentlyContinue
    $pendingComp = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name 'ComputerName' -ErrorAction SilentlyContinue
    $compRenamePending = [bool]($actComp -and $pendingComp -and ($actComp -ne $pendingComp))

    # 5. PendingFileRenameOperations (Filtered to ignore deletes; source: https://stackoverflow.com/a/68627581)
    $fileRenamePending = $false
    $sessionManager = Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
    $rawRenameOps = if ($sessionManager) { $sessionManager.GetValue('PendingFileRenameOperations') }
    if ($rawRenameOps) {
        $pairCount = [int]($rawRenameOps.Length / 2)
        for ($i = 0; $i -lt $pairCount; $i++) {
            $destination = $rawRenameOps[$i * 2 + 1]
            if (-not [string]::IsNullOrEmpty($destination)) {
                $fileRenamePending = $true
                break
            }
        }
    }

    return ($cbsPending -or $windowsUpdate -or $msiPending -or $compRenamePending -or $fileRenamePending)
}



