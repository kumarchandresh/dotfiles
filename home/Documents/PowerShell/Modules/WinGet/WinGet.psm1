#requires -PSEdition Core

Import-Module 'Microsoft.WinGet.Client'
Import-Module "$PSScriptRoot/../Utils"

function Test-IsWinGetPackageInstalled {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter()]
        [string]$Source = 'winget'
    )

    $params = @{
        Id          = $Id
        MatchOption = 'Equals'
    }
    if (-not [string]::IsNullOrEmpty($Source)) {
        $params['Source'] = $Source
    }

    [bool](Get-WinGetPackage @params)
}

function Install-WinGetPackage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [string]$Id,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$InstallerType,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Custom,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Override,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Location,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Source = 'winget',

        [Parameter(ValueFromPipelineByPropertyName)]
        [switch]$Global,

        [Parameter(ValueFromPipelineByPropertyName)]
        [switch]$SavePrefs
    )

    process {
        $scope = if ($Global) { 'System' } else { 'User' }

        # 1. Check existing installation
        $getPackageParams = @{
            Id          = $Id
            MatchOption = 'Equals'
        }
        if (-not [string]::IsNullOrEmpty($Source)) {
            $getPackageParams['Source'] = $Source
        }
        $installed = Get-WinGetPackage @getPackageParams

        if ($installed -and (-not $SavePrefs) -and (-not $installed.IsUpdateAvailable)) {
            Write-Green "$Id is already up to date"
            return
        }

        # 2. Resolve installer type if needed
        $type = $InstallerType
        if (-not $type) {
            if (Test-Path (Join-Path $PSScriptRoot "Prefs/$Id.inf")) {
                $type = 'inno'
            }
            elseif (Test-Path (Join-Path $PSScriptRoot "Prefs/$Id.txt")) {
                $type = 'wix'
            }
            elseif ($Custom -and $Custom.EndsWith('.inf', [System.StringComparison]::OrdinalIgnoreCase)) {
                $type = 'inno'
            }
            elseif ($Custom -and $Custom.EndsWith('.txt', [System.StringComparison]::OrdinalIgnoreCase)) {
                $type = 'wix'
            }
        }

        if (-not $type -and ($SavePrefs -or ($Custom -and $Custom.StartsWith('file:', [System.StringComparison]::OrdinalIgnoreCase)))) {
            $cliScope = if ($Global) { 'machine' } else { 'user' }
            $cliArgs = @('--exact', '--id', $Id, '--scope', $cliScope, '--accept-source-agreements', '--disable-interactivity')
            if (-not [string]::IsNullOrEmpty($Source)) {
                $cliArgs += @('--source', $Source)
            }

            $info = & winget show @cliArgs | Out-String
            if ($info -match 'Installer\s*Type:\s+(.*)') {
                $type = $matches[1].Trim().ToLower()
            }
        }

        # 3. Construct base cmdlet parameters
        $cmdletParams = [ordered]@{
            Id          = $Id
            MatchOption = 'Equals'
            Scope       = $scope
        }

        if (-not [string]::IsNullOrEmpty($Source)) {
            $cmdletParams['Source'] = $Source
        }
        if (-not [string]::IsNullOrEmpty($Location)) {
            $cmdletParams['Location'] = $Location
        }
        if ($PSBoundParameters.ContainsKey('InstallerType')) {
            $cmdletParams['InstallerType'] = $InstallerType
        }

        # 4. Handle -SavePrefs (Authoring Mode) or Configuration Arguments
        if ($SavePrefs) {
            if (($Custom -and $Custom.StartsWith('file:', [System.StringComparison]::OrdinalIgnoreCase)) -or
                ($Override -and $Override.StartsWith('file:', [System.StringComparison]::OrdinalIgnoreCase))) {
                Write-Red "Cannot load a config file and specify -SavePrefs at the same time."
                return
            }

            $ext = switch ($type) {
                'inno' { '.inf' }
                { $_ -in @('wix', 'burn') } { '.txt' }
                default { $null }
            }

            if (-not $ext) {
                Write-Red "Saving config is not supported for installer type: $type"
                return
            }

            $targetFile = Join-Path $PSScriptRoot "Prefs/$Id$ext"
            $targetDir = Split-Path -Path $targetFile -Parent
            if ($targetDir -and -not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            switch ($type) {
                'inno' {
                    $cmdletParams['Mode'] = 'Interactive'
                    $cmdletParams['Custom'] = "/SAVEINF=`"$targetFile`""
                }
                { $_ -in @('wix', 'burn') } {
                    $logDir = Join-Path $env:TEMP 'Logs'
                    if (-not (Test-Path $logDir)) {
                        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
                    }
                    $cmdletParams['Mode'] = 'Interactive'
                    $cmdletParams['Custom'] = "/log `"$logDir\$Id.log`""
                }
            }
        }
        else {
            # Resolve -Override
            if ($Override) {
                if ($Override.StartsWith('file:', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $filePath = $Override.Substring(5).Trim()
                    if (-not [System.IO.Path]::IsPathRooted($filePath)) {
                        $filePath = Join-Path $PSScriptRoot "Prefs/$filePath"
                    }
                    if (-not (Test-Path $filePath)) {
                        Write-Red "Preference file not found: $filePath"
                        return
                    }
                    $content = (Get-Content -Path $filePath) -join ' '
                    $cmdletParams['Override'] = [System.Environment]::ExpandEnvironmentVariables($content)
                }
                else {
                    $cmdletParams['Override'] = $Override
                }
            }

            # Resolve -Custom
            if ($Custom) {
                if ($Custom.StartsWith('file:', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $filePath = $Custom.Substring(5).Trim()
                    if (-not [System.IO.Path]::IsPathRooted($filePath)) {
                        $filePath = Join-Path $PSScriptRoot "Prefs/$filePath"
                    }
                    if (-not (Test-Path $filePath)) {
                        Write-Red "Preference file not found: $filePath"
                        return
                    }

                    if ($type -eq 'inno' -or $filePath.EndsWith('.inf', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $cmdletParams['Custom'] = "/LOADINF=`"$filePath`""
                    }
                    else {
                        $content = (Get-Content -Path $filePath) -join ' '
                        $cmdletParams['Custom'] = [System.Environment]::ExpandEnvironmentVariables($content)
                    }
                }
                else {
                    $cmdletParams['Custom'] = $Custom
                }
            }
            elseif (-not $Override) {
                # Auto-discovery fallback if neither -Custom nor -Override was provided
                $autoInf = Join-Path $PSScriptRoot "Prefs/$Id.inf"
                $autoTxt = Join-Path $PSScriptRoot "Prefs/$Id.txt"

                if (Test-Path $autoInf) {
                    $cmdletParams['Custom'] = "/LOADINF=`"$autoInf`""
                }
                elseif (Test-Path $autoTxt) {
                    $content = (Get-Content -Path $autoTxt) -join ' '
                    $cmdletParams['Custom'] = [System.Environment]::ExpandEnvironmentVariables($content)
                }
            }
        }

        # 5. Dispatch execution
        if ($installed -and $SavePrefs) {
            $cmdletParams['Force'] = $true
        }

        $displayArgs = ($cmdletParams.GetEnumerator() | ForEach-Object {
                if ($_.Value -is [bool] -or $_.Value -is [System.Management.Automation.SwitchParameter]) {
                    if ($_.Value) { "-$($_.Key)" }
                }
                elseif ($_.Value -is [string] -and $_.Value -match '\s') {
                    "-$($_.Key) `"$($_.Value)`""
                }
                else {
                    "-$($_.Key) $($_.Value)"
                }
            }) -join ' '
        $action = if ($installed -and (-not $SavePrefs)) { 'Update' } else { 'Install' }

        Write-Muted "$([char]0x203A) $action-WinGetPackage $displayArgs"
        & "Microsoft.WinGet.Client\$action-WinGetPackage" @cmdletParams
    }
}

Export-ModuleMember -Function Test-IsWinGetPackageInstalled, Install-WinGetPackage
