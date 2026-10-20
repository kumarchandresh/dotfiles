function Test-IsProcessElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restore-EnvPath {
    # https://superuser.com/q/867728/1042970
    # Windows is crazy; it prepends system path to user path; which results in
    # system applications taking precedence over user applications.
    ${env:Path} = @(
        [Environment]::GetEnvironmentVariable('Path', 'User')
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
    ) -join ';'
}

function Write-ColorOutput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline = $true)]
        [object]$Object,
        [Parameter()]
        [ValidateSet(
            'Black', 'Blue', 'Cyan', 'Gray', 'Green', 'Magenta', 'Red', 'White', 'Yellow',
            'DarkBlue', 'DarkCyan', 'DarkGray', 'DarkGreen', 'DarkMagenta', 'DarkRed', 'DarkYellow'
        )]
        [System.ConsoleColor]$ForegroundColor,
        [Parameter()]
        [ValidateSet(
            'Black', 'Blue', 'Cyan', 'Gray', 'Green', 'Magenta', 'Red', 'White', 'Yellow',
            'DarkBlue', 'DarkCyan', 'DarkGray', 'DarkGreen', 'DarkMagenta', 'DarkRed', 'DarkYellow'
        )]
        [System.ConsoleColor]$BackgroundColor,
        [Parameter()]
        [switch]$NoNewLine
    )

    $prevForegroundColor = $Host.UI.RawUI.ForegroundColor
    $prevBackgroundColor = $Host.UI.RawUI.BackgroundColor

    if ($null -ne $ForegroundColor) {
        $Host.UI.RawUI.ForegroundColor = $ForegroundColor
    }
    if ($null -ne $BackgroundColor) {
        $Host.UI.RawUI.BackgroundColor = $BackgroundColor
    }

    if ($NoNewLine) {
        Write-Output $Object
    }
    else {
        Write-Output $Object
    }

    $Host.UI.RawUI.ForegroundColor = $prevForegroundColor
    $Host.UI.RawUI.BackgroundColor = $prevBackgroundColor
}

function Write-Title {
    Write-Output ''
    Write-ColorOutput $args -ForegroundColor Cyan
}

function Write-Blue { Write-ColorOutput $args -ForegroundColor Blue }
function Write-Cyan { Write-ColorOutput $args -ForegroundColor Cyan }
function Write-Text { Write-ColorOutput $args -ForegroundColor Gray }
function Write-Green { Write-ColorOutput $args -ForegroundColor Green }
function Write-Magenta { Write-ColorOutput $args -ForegroundColor Magenta }
function Write-Red { Write-ColorOutput $args -ForegroundColor Red }
function Write-White { Write-ColorOutput $args -ForegroundColor White }
function Write-Yellow { Write-ColorOutput $args -ForegroundColor Yellow }
function Write-DarkBlue { Write-ColorOutput $args -ForegroundColor DarkBlue }
function Write-DarkCyan { Write-ColorOutput $args -ForegroundColor DarkCyan }
function Write-Muted { Write-ColorOutput $args -ForegroundColor DarkGray }
function Write-DarkGreen { Write-ColorOutput $args -ForegroundColor DarkGreen }
function Write-DarkMagenta { Write-ColorOutput $args -ForegroundColor DarkMagenta }
function Write-DarkRed { Write-ColorOutput $args -ForegroundColor DarkRed }
function Write-DarkYellow { Write-ColorOutput $args -ForegroundColor DarkYellow }

function Test-IsCommandAvailable {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Command
    )

    [bool](Get-Command -Name $Command -ErrorAction SilentlyContinue)
}

function Test-IsWslAvailable {
    if (-not (Test-IsCommandAvailable 'wsl')) {
        return $false
    }

    $status = (wsl --status 2>&1 | Out-String) -replace "`0", ''
    return [bool]($status -match 'Default Version:\s+[12]')
}

# https://stackoverflow.com/a/47869761
# https://stackoverflow.com/a/68627581
function Test-IsRebootPending {
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



