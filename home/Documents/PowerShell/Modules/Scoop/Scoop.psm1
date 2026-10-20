Import-Module "$PSScriptRoot/../Utils"

function Test-ScoopPackageInstalled {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )

    $scoopDir = if ($env:SCOOP) { $env:SCOOP } else { "$HOME/scoop" }
    $globalDir = if ($env:SCOOP_GLOBAL) { $env:SCOOP_GLOBAL } else { "$env:ProgramData/scoop" }

    if ((Test-Path (Join-Path $scoopDir "apps/$Name")) -or (Test-Path (Join-Path $globalDir "apps/$Name"))) {
        return $true
    }

    return [bool](scoop list | Where-Object -Property Name -eq $Name)
}

function Install-ScoopPackage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$Package,
        [Parameter()]
        [switch]$Global
    )

    process {

        switch -Regex ($Package) {
            # URL format: https://example.com/app.json@version
            '^(?:https?://)?.+/([^/@]+)\.json((?:@).*)?$' {
                $name = $Matches[1]
                break
            }
            # Path format: C:/path/to/app.json@version
            '^.+[\\/]([^\\/@]+)\.json(@.*)?$' {
                $name = $Matches[1]
                break
            }
            # Bucket format: bucket/app@version
            '^[^/]+/([^@]+)(@.*)?$' {
                $name = $Matches[1]
                break
            }
            # Short format: app@version
            '^([^@]+)(@.*)?$' {
                $name = $Matches[1]
                break
            }
            default {
                $name = $Package
                break
            }
        }

        $installed = Test-ScoopPackageInstalled $name
        $arguments = @(if ($installed) { 'update' } else { 'install' })
        if ($Global) {
            $arguments += '--global'
        }
        $arguments += $Package

        if ($installed) {
            $output = (& scoop @arguments *>&1 | Out-String)
            if ($output -match '\(latest version\)') {
                Write-Muted "~ scoop/$Package"
            }
            else {
                Write-Green "^ scoop/$Package"
                Write-Muted "$([char]0x203A) scoop $($arguments -join ' ')"
                if ($output) { Write-Output $output.Trim() }
            }
        }
        else {
            Write-Green "+ scoop/$Package"
            Write-Muted "$([char]0x203A) scoop $($arguments -join ' ')"
            & scoop @arguments
        }
    }
}

function Test-ScoopBucketInstalled {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )

    $scoopDir = if ($env:SCOOP) { $env:SCOOP } else { "$HOME/scoop" }
    if (Test-Path (Join-Path $scoopDir "buckets/$Name")) {
        return $true
    }

    return [bool](scoop bucket list | Where-Object -Property Name -eq $Name)
}

function Install-ScoopBucket {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipelineByPropertyName, Mandatory)]
        [string]$Name,
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Repo
    )

    process {
        $scoopDir = if ($env:SCOOP) { $env:SCOOP } else { "$HOME/scoop" }
        if (-not (Test-Path (Join-Path $scoopDir "buckets/$Name/.git"))) {
            if (Test-Path (Join-Path $scoopDir "buckets/$Name")) {
                Write-Red "- scoop/bucket/$Name"
                Write-Muted "$([char]0x203A) scoop bucket rm $Name"
                scoop bucket rm $Name
            }
            Write-Green "+ scoop/bucket/$Name"
            if ($Repo) {
                Write-Muted "$([char]0x203A) scoop bucket add $Name $Repo"
                scoop bucket add $Name $Repo
            }
            else {
                Write-Muted "$([char]0x203A) scoop bucket add $Name"
                scoop bucket add $Name
            }
        }
        else {
            Write-Muted "~ scoop/bucket/$Name"
        }
    }
}
