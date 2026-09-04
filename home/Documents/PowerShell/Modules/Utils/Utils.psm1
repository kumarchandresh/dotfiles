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

function Test-IsProcessElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
