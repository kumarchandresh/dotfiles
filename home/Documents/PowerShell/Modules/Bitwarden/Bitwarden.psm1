Import-Module "$PSScriptRoot/../Utils"

function Unlock-Bitwarden {
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    if (-not (Test-IsCommandAvailable bw)) {
        Write-Error 'Bitwarden CLI is not on PATH; aborted.' -Category NotInstalled
        return 'Failed'
    }

    :loop while ($true) {
        $retry = 'y'

        $bw = bw status | ConvertFrom-Json
        $exitCode = $LASTEXITCODE
        $status = $bw.status

        switch ($status) {
            'unauthenticated' {
                $sessionId = bw login --raw
                $exitCode = $LASTEXITCODE
                break
            }
            'locked' {
                $sessionId = bw unlock --raw
                $exitCode = $LASTEXITCODE
                break
            }
            'unlocked' {
                Write-Green 'Bitwarden is already unlocked'
                return 'AlreadyUnlocked'
            }
            default {
                throw "Uh, oh! What to do when status is '$status'?"
            }
        }

        if ($exitCode -eq 0) {
            Write-Green 'Bitwarden unlocked successfully'
            [System.Environment]::SetEnvironmentVariable('BW_SESSION', $sessionId, [System.EnvironmentVariableTarget]::Process)
            [System.Environment]::SetEnvironmentVariable('BW_SESSION', $sessionId, [System.EnvironmentVariableTarget]::User)
            return 'Unlocked'
        }
        else {
            Write-Red 'Failed to unlock Bitwarden'
            $choice = Read-Host 'Try again? (Y/n)'

            if ($choice.Length) {
                $retry = $choice.ToLower().Substring(0, 1)
            }
        }

        if ($retry -eq 'n') {
            return 'Failed'
        }
    }
}

function Lock-Bitwarden {
    [System.Environment]::SetEnvironmentVariable('BW_SESSION', $null, [System.EnvironmentVariableTarget]::Process)
    [System.Environment]::SetEnvironmentVariable('BW_SESSION', $null, [System.EnvironmentVariableTarget]::User)
}
