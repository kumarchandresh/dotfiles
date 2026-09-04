Import-Module "$PSScriptRoot/../Utils"

function Test-IsScoopPackageInstalled {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )

    [bool](scoop list | Where-Object -Property Name -eq $Name)
}

function Install-ScoopPackage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Package,
        [Parameter()]
        [switch]$Global
    )

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

    $arguments = @(if (Test-IsScoopPackageInstalled $name) { 'update' } else { 'install' })
    if ($Global) {
        $arguments += '--global'
    }
    $arguments += $Package

    Write-Muted "scoop $($arguments -join ' ')"
    & scoop @arguments
}

function Test-IsBucketInstalled {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )

    [bool](scoop bucket list | Where-Object -Property Name -eq $Name)
}

function Install-ScoopBucket {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipelineByPropertyName, Mandatory)]
        [string]$Name,
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Repo
    )

    if (-not (Test-Path "$HOME/scoop/buckets/$name/.git")) {
        if (Test-Path "$HOME/scoop/buckets/$name") {
            Write-Red "- bucket/$Name"
            scoop bucket rm $Name
        }
        Write-Green "+ bucket/$Name"
        if ($Repo) {
            scoop bucket add $Name $Repo
        }
        else {
            scoop bucket add $Name
        }
    }
    else {
        Write-Muted "~ bucket/$Name"
    }
}
