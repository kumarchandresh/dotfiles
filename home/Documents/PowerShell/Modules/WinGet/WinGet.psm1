Import-Module "$PSScriptRoot/../Utils"

#region using winget-ps
if ($PSEdition -eq 'Core') {
    Import-Module 'Microsoft.WinGet.Client'

    function Test-WinGetPackageInstalled {
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

        return [bool](Get-WinGetPackage @params)
    }

    function Install-WinGetPackage {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
            [string]$Id,

            [Parameter(ValueFromPipelineByPropertyName)]
            [string]$InstallerType,

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
                Write-Muted "~ winget/$Id"
                return
            }

            # 2. Resolve installer type if needed
            $type = $InstallerType
            if (-not $type) {
                if ((Test-Path (Join-Path $PSScriptRoot "Prefs/$Id.override.inf")) -or (Test-Path (Join-Path $PSScriptRoot "Prefs/$Id.custom.inf"))) {
                    $type = 'inno'
                }
                elseif ((Test-Path (Join-Path $PSScriptRoot "Prefs/$Id.override.txt")) -or (Test-Path (Join-Path $PSScriptRoot "Prefs/$Id.custom.txt"))) {
                    $type = 'wix'
                }
            }

            if (-not $type -and $SavePrefs) {
                $cliScope = if ($Global) { 'machine' } else { 'user' }
                $cliArgs = @('--exact', '--id', $Id, '--scope', $cliScope, '--accept-source-agreements', '--disable-interactivity')
                if (-not [string]::IsNullOrEmpty($Source)) {
                    $cliArgs += @('--source', $Source)
                }

                $info = & winget show @cliArgs 2>$null | Out-String
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($info) -or $info -match 'No package found') {
                    Write-Red "Package '$Id' not found."
                    return
                }
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
            if (-not [string]::IsNullOrEmpty($InstallerType)) {
                $cmdletParams['InstallerType'] = $InstallerType
            }

            # 4. Handle -SavePrefs (Authoring Mode) or Implicit Prefs
            if ($SavePrefs) {
                $ext = switch ($type) {
                    'inno' { '.inf' }
                    { $_ -in @('wix', 'burn') } { '.txt' }
                    default { $null }
                }

                if (-not $ext) {
                    $typeMsg = if ($type) { $type } else { 'unknown' }
                    Write-Red "Saving config is not supported for installer type: $typeMsg"
                    return
                }

                $targetFile = Join-Path $PSScriptRoot "Prefs/$Id.custom$ext"
                $targetDir = Split-Path -Path $targetFile -Parent
                if ($targetDir -and -not (Test-Path $targetDir)) {
                    $null = New-Item -ItemType Directory -Path $targetDir -Force
                }

                switch ($type) {
                    'inno' {
                        $cmdletParams['Mode'] = 'Interactive'
                        $cmdletParams['Custom'] = "/SAVEINF=`"$targetFile`""
                    }
                    { $_ -in @('wix', 'burn') } {
                        $logDir = Join-Path $env:TEMP 'Logs'
                        if (-not (Test-Path $logDir)) {
                            $null = New-Item -ItemType Directory -Path $logDir -Force
                        }
                        $cmdletParams['Mode'] = 'Interactive'
                        $cmdletParams['Custom'] = "/log `"$logDir\$Id.log`""
                    }
                }
            }
            else {
                # Implicit preference loading based on convention
                $prefFile = $null
                $prefMode = $null
                $prefKind = $null

                $overrideInf = Join-Path $PSScriptRoot "Prefs/$Id.override.inf"
                $overrideTxt = Join-Path $PSScriptRoot "Prefs/$Id.override.txt"
                $customInf = Join-Path $PSScriptRoot "Prefs/$Id.custom.inf"
                $customTxt = Join-Path $PSScriptRoot "Prefs/$Id.custom.txt"

                if (Test-Path $overrideInf) {
                    $prefFile = $overrideInf
                    $prefMode = 'Override'
                    $prefKind = 'inf'
                }
                elseif (Test-Path $overrideTxt) {
                    $prefFile = $overrideTxt
                    $prefMode = 'Override'
                    $prefKind = 'txt'
                }
                elseif (Test-Path $customInf) {
                    $prefFile = $customInf
                    $prefMode = 'Custom'
                    $prefKind = 'inf'
                }
                elseif (Test-Path $customTxt) {
                    $prefFile = $customTxt
                    $prefMode = 'Custom'
                    $prefKind = 'txt'
                }

                if ($prefFile) {
                    if ($prefKind -eq 'inf') {
                        $cmdletParams[$prefMode] = "/LOADINF=`"$prefFile`""
                    }
                    else {
                        $content = (Get-Content -Path $prefFile) -join ' '
                        $cmdletParams[$prefMode] = [System.Environment]::ExpandEnvironmentVariables($content)
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

            if ($action -eq 'Update') {
                Write-Green "^ winget/$Id"
            }
            else {
                Write-Green "+ winget/$Id"
            }
            Write-Muted "$([char]0x203A) $action-WinGetPackage $displayArgs"
            & "Microsoft.WinGet.Client\$action-WinGetPackage" @cmdletParams | Out-Host
        }
    }
}
#endregion
#region using winget.exe
else {
    function Test-WinGetPackageInstalled {
        [CmdletBinding()]
        [OutputType([bool])]
        param (
            [Parameter(Mandatory)]
            [string]$Id,

            [Parameter()]
            [string]$Source = 'winget'
        )

        $cliArgs = @('list', '--exact', '--id', $Id, '--accept-source-agreements')
        if (-not [string]::IsNullOrEmpty($Source)) {
            $cliArgs += @('--source', $Source)
        }

        & winget @cliArgs *>$null
        return ($LASTEXITCODE -eq 0)
    }

    function Test-WinGetPackageUpdateAvailable {
        [CmdletBinding()]
        [OutputType([bool])]
        param (
            [Parameter(Mandatory)]
            [string]$Id,

            [Parameter()]
            [string]$Source = 'winget'
        )

        $cliArgs = @('list', '--exact', '--id', $Id, '--upgrade-available', '--accept-source-agreements')
        if (-not [string]::IsNullOrEmpty($Source)) {
            $cliArgs += @('--source', $Source)
        }

        $output = & winget @cliArgs 2>$null | Out-String
        return [bool]($output -match '\d+ upgrades? available')
    }

    function Install-WinGetPackage {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
            [string]$Id,

            [Parameter(ValueFromPipelineByPropertyName)]
            [string]$InstallerType,

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
            $scope = if ($Global) { 'machine' } else { 'user' }

            # 1. Check existing installation
            $package = @{ Id = $Id }
            if (-not [string]::IsNullOrEmpty($Source)) {
                $package['Source'] = $Source
            }

            $installed = Test-WinGetPackageInstalled @package
            $updateAvailable = if ($installed) { Test-WinGetPackageUpdateAvailable @package } else { $false }

            if ($installed -and (-not $SavePrefs) -and (-not $updateAvailable)) {
                Write-Muted "~ winget/$Id"
                return
            }

            # 2. Resolve installer type if needed
            $type = $InstallerType
            if (-not $type) {
                if ((Test-Path (Join-Path $PSScriptRoot "Prefs/$Id.override.inf")) -or (Test-Path (Join-Path $PSScriptRoot "Prefs/$Id.custom.inf"))) {
                    $type = 'inno'
                }
                elseif ((Test-Path (Join-Path $PSScriptRoot "Prefs/$Id.override.txt")) -or (Test-Path (Join-Path $PSScriptRoot "Prefs/$Id.custom.txt"))) {
                    $type = 'wix'
                }
            }

            # Query show info if installer type is needed for prefs
            if (-not $type -and $SavePrefs) {
                $cliShowArgs = @('--exact', '--id', $Id, '--scope', $scope, '--accept-source-agreements', '--disable-interactivity')
                if (-not [string]::IsNullOrEmpty($Source)) {
                    $cliShowArgs += @('--source', $Source)
                }

                $info = & winget show @cliShowArgs 2>$null | Out-String
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($info) -or $info -match 'No package found') {
                    Write-Red "Package '$Id' not found."
                    return
                }
                if ($info -match 'Installer\s*Type:\s+(.*)') {
                    $type = $matches[1].Trim().ToLower()
                }
            }

            # 3. Construct install/upgrade arguments
            $cliArgs = @('--exact', '--id', $Id, '--scope', $scope, '--accept-source-agreements', '--accept-package-agreements')
            if (-not [string]::IsNullOrEmpty($Source)) {
                $cliArgs += @('--source', $Source)
            }
            if (-not [string]::IsNullOrEmpty($Location)) {
                $cliArgs += @('--location', $Location)
            }
            if (-not [string]::IsNullOrEmpty($InstallerType)) {
                $cliArgs += @('--installer-type', $InstallerType)
            }

            # 4. Handle -SavePrefs or Implicit Prefs
            if ($SavePrefs) {
                $cliArgs += @('--interactive')

                $ext = switch ($type) {
                    'inno' { '.inf' }
                    { $_ -in @('wix', 'burn') } { '.txt' }
                    default { $null }
                }

                if (-not $ext) {
                    $typeMsg = if ($type) { $type } else { 'unknown' }
                    Write-Red "Saving config is not supported for installer type: $typeMsg"
                    return
                }

                $targetFile = Join-Path $PSScriptRoot "Prefs/$Id.custom$ext"
                $targetDir = Split-Path -Path $targetFile -Parent
                if ($targetDir -and -not (Test-Path $targetDir)) {
                    $null = New-Item -ItemType Directory -Path $targetDir -Force
                }

                switch ($type) {
                    'inno' {
                        $cliArgs += @('--custom', "/SAVEINF=`"$targetFile`"")
                    }
                    { $_ -in @('wix', 'burn') } {
                        $logDir = Join-Path $env:TEMP 'Logs'
                        if (-not (Test-Path $logDir)) {
                            $null = New-Item -ItemType Directory -Path $logDir -Force
                        }
                        $cliArgs += @('--custom', "/log `"$logDir\$Id.log`"")
                    }
                }
            }
            else {
                $cliArgs += @('--disable-interactivity')

                # Implicit preference loading based on convention
                $prefFile = $null
                $prefMode = $null
                $prefKind = $null

                $overrideInf = Join-Path $PSScriptRoot "Prefs/$Id.override.inf"
                $overrideTxt = Join-Path $PSScriptRoot "Prefs/$Id.override.txt"
                $customInf = Join-Path $PSScriptRoot "Prefs/$Id.custom.inf"
                $customTxt = Join-Path $PSScriptRoot "Prefs/$Id.custom.txt"

                if (Test-Path $overrideInf) {
                    $prefFile = $overrideInf
                    $prefMode = 'Override'
                    $prefKind = 'inf'
                }
                elseif (Test-Path $overrideTxt) {
                    $prefFile = $overrideTxt
                    $prefMode = 'Override'
                    $prefKind = 'txt'
                }
                elseif (Test-Path $customInf) {
                    $prefFile = $customInf
                    $prefMode = 'Custom'
                    $prefKind = 'inf'
                }
                elseif (Test-Path $customTxt) {
                    $prefFile = $customTxt
                    $prefMode = 'Custom'
                    $prefKind = 'txt'
                }

                if ($prefFile) {
                    $flag = if ($prefMode -eq 'Override') { '--override' } else { '--custom' }
                    if ($prefKind -eq 'inf') {
                        $cliArgs += @($flag, "/LOADINF=`"$prefFile`"")
                    }
                    else {
                        $content = (Get-Content -Path $prefFile) -join ' '
                        $cliArgs += @($flag, [System.Environment]::ExpandEnvironmentVariables($content))
                    }
                }
            }

            # 5. Dispatch execution
            if ($installed -and $SavePrefs) {
                $cliArgs += @('--force')
            }

            $action = if ($installed -and (-not $SavePrefs)) { 'upgrade' } else { 'install' }

            if ($action -eq 'upgrade') {
                Write-Green "^ winget/$Id"
            }
            else {
                Write-Green "+ winget/$Id"
            }
            Write-Muted "$([char]0x203A) winget $action $($cliArgs -join ' ')"
            & winget $action @cliArgs | Out-Host
        }
    }
}
#endregion

Export-ModuleMember -Function Test-WinGetPackageInstalled, Install-WinGetPackage
