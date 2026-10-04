Import-Module 'Microsoft.WinGet.Client'
Import-Module "$PSScriptRoot/../../Modules/Utils"

function Test-IsWinGetPackageInstalled {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Id
    )

    [bool](Get-WinGetPackage -MatchOption Equals -Id $Id)
}

function Install-WinGetPackage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$Id,

        [Parameter()]
        [ValidateSet('exe', 'zip', 'inno', 'nullsoft', 'msi', 'wix', 'appx', 'msix', 'burn', 'portable')]
        [string]$InstallerType,

        [Parameter()]
        [string]$Config,

        [Parameter()]
        [string]$Location,

        [Parameter()]
        [switch]$Override,

        [Parameter()]
        [switch]$Global,

        [Parameter()]
        [switch]$SaveConfig
    )

    process {

        $scope = if ($Global) { 'System' } else { 'User' }

        # 1. Base parameters for Microsoft.WinGet.Client
        $wingetParams = [ordered]@{
            Id          = $Id
            MatchOption = 'Equals'
            Scope       = $scope
        }

        if ($PSBoundParameters.ContainsKey('InstallerType')) {
            $wingetParams['InstallerType'] = $InstallerType
        }

        if (![string]::IsNullOrEmpty($Location)) {
            $wingetParams['Location'] = $Location
        }

        # 2. Check if already installed
        $installed = Get-WinGetPackage -MatchOption Equals -Id $Id

        # 3. Resolve Config file path if provided
        $installerConfig = if ($PSBoundParameters.ContainsKey('Config')) {
            if ([System.IO.Path]::IsPathRooted($Config)) {
                $Config
            }
            else {
                Join-Path $PSScriptRoot "Config/$Config"
            }
        }

        # 4. Handle Arguments
        if ($Override) {
            if ($installerConfig -and (Test-Path $installerConfig)) {
                $argsString = (Get-Content -Path $installerConfig) -join ' '
                $wingetParams['Override'] = [System.Environment]::ExpandEnvironmentVariables($argsString)
            }
            elseif ($installerConfig) {
                Write-Red "Config file not found: $installerConfig"
                return
            }
        }
        elseif ($installerConfig) {
            $showScope = if ($Global) { 'machine' } else { 'user' }
            $showArgs = @('--exact', '--id', $Id, '--scope', $showScope)
            if ($PSBoundParameters.ContainsKey('InstallerType')) {
                $showArgs += @('--installer-type', $InstallerType)
            }

            $info = & winget show @showArgs | Out-String
            $type = if ($info -match 'Installer\s*Type:\s+(.*)') {
                $matches[1].Trim().ToLower()
            }

            switch ($type) {
                'inno' {
                    if ($SaveConfig) {
                        $wingetParams['Mode'] = 'Interactive'
                        $wingetParams['Custom'] = "/SAVEINF=`"$installerConfig`""
                    }
                    elseif (Test-Path $installerConfig) {
                        $wingetParams['Custom'] = "/LOADINF=`"$installerConfig`""
                    }
                    else {
                        Write-Red "Config file not found: $installerConfig"
                        return
                    }
                }
                { $_ -in @('wix', 'burn') } {
                    if ($SaveConfig) {
                        $logsDir = Join-Path $env:TEMP 'Logs'
                        if (-not (Test-Path $logsDir)) {
                            New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
                        }
                        $wingetParams['Mode'] = 'Interactive'
                        $wingetParams['Custom'] = "/log `"$logsDir\$Id.log`""
                    }
                    elseif (Test-Path $installerConfig) {
                        $fileContent = (Get-Content -Path $installerConfig) -join ' '
                        $wingetParams['Custom'] = [System.Environment]::ExpandEnvironmentVariables($fileContent)
                    }
                    else {
                        Write-Red "Config file not found: $installerConfig"
                        return
                    }
                }
                default {
                    if (Test-Path $installerConfig) {
                        Write-Red "Config file is not supported for installer type: $type"
                        return
                    }
                }
            }
        }

        # 5. Dispatch to Microsoft.WinGet.Client
        $params = ($wingetParams.GetEnumerator() | ForEach-Object {
                if ($_.Value -is [string] -and $_.Value -match '\s') {
                    "-$($_.Key) `"$($_.Value)`""
                }
                else {
                    "-$($_.Key) $($_.Value)"
                }
            }) -join ' '

        if ($installed) {
            if ($installed.IsUpdateAvailable) {
                Write-Muted "$([char]0x203A) Update-WinGetPackage $params"
                Microsoft.WinGet.Client\Update-WinGetPackage @wingetParams
            }
            else {
                Write-Green "$Id is already up to date"
            }
        }
        else {
            Write-Muted "$([char]0x203A) Install-WinGetPackage $params"
            Microsoft.WinGet.Client\Install-WinGetPackage @wingetParams
        }
    }
}
