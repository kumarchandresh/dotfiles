Import-Module "$PSScriptRoot/../Utils"

function Get-WslDistro {
    [CmdletBinding()]
    [OutputType([string[]])]
    param ()

    if (-not (Test-WslAvailable)) {
        return @()
    }

    return @(wsl --list --quiet 2>$null) -replace "`0", '' |
        Where-Object { $_ -match '\S' } |
        ForEach-Object { $_.Trim() }
}

function Install-WslDistro {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string[]]$Name
    )

    begin {
        $distros = Get-WslDistro
    }

    process {
        foreach ($distroName in $Name) {
            if ($distroName -notin $distros) {
                Write-Green "+ WSL/$distroName"
                Write-Muted "$([char]0x203A) wsl --install $distroName --no-launch"
                wsl --install $distroName --no-launch
            }
            else {
                Write-Muted "~ WSL/$distroName"
            }
        }
    }
}

function Update-Wsl {
    [CmdletBinding()]
    param ()

    Write-Muted "$([char]0x203A) wsl --update"
    wsl --update
}

Export-ModuleMember -Function Get-WslDistro, Install-WslDistro, Update-Wsl
