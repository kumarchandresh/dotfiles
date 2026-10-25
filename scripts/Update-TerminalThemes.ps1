$SettingsPath = "$PSScriptRoot/../home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"

Import-Module -Force "$PSScriptRoot/../home/Documents/PowerShell/Modules/Utils"

$themes = @(
    @{
        Name      = 'catppuccin-frappe'
        SchemeUrl = 'https://raw.githubusercontent.com/catppuccin/windows-terminal/refs/heads/main/frappe.json'
        ThemeUrl  = 'https://raw.githubusercontent.com/catppuccin/windows-terminal/refs/heads/main/frappeTheme.json'
    },
    @{
        Name      = 'catppuccin-latte'
        SchemeUrl = 'https://raw.githubusercontent.com/catppuccin/windows-terminal/refs/heads/main/latte.json'
        ThemeUrl  = 'https://raw.githubusercontent.com/catppuccin/windows-terminal/refs/heads/main/latteTheme.json'
    },
    @{
        Name      = 'catppuccin-macchiato'
        SchemeUrl = 'https://raw.githubusercontent.com/catppuccin/windows-terminal/refs/heads/main/macchiato.json'
        ThemeUrl  = 'https://raw.githubusercontent.com/catppuccin/windows-terminal/refs/heads/main/macchiatoTheme.json'
    },
    @{
        Name      = 'catppuccin-mocha'
        SchemeUrl = 'https://raw.githubusercontent.com/catppuccin/windows-terminal/refs/heads/main/mocha.json'
        ThemeUrl  = 'https://raw.githubusercontent.com/catppuccin/windows-terminal/refs/heads/main/mochaTheme.json'
    },
    @{
        Name      = 'rose-pine'
        SchemeUrl = 'https://raw.githubusercontent.com/rose-pine/windows-terminal/refs/heads/main/rose-pine.scheme.json'
        ThemeUrl  = 'https://raw.githubusercontent.com/rose-pine/windows-terminal/refs/heads/main/rose-pine.theme.json'
    },
    @{
        Name      = 'rose-pine-dawn'
        SchemeUrl = 'https://raw.githubusercontent.com/rose-pine/windows-terminal/refs/heads/main/rose-pine-dawn.scheme.json'
        ThemeUrl  = 'https://raw.githubusercontent.com/rose-pine/windows-terminal/refs/heads/main/rose-pine-dawn.theme.json'
    },
    @{
        Name      = 'rose-pine-moon'
        SchemeUrl = 'https://raw.githubusercontent.com/rose-pine/windows-terminal/refs/heads/main/rose-pine-moon.scheme.json'
        ThemeUrl  = 'https://raw.githubusercontent.com/rose-pine/windows-terminal/refs/heads/main/rose-pine-moon.theme.json'
    }
)

if (-not (Test-Path -Path $SettingsPath)) {
    Write-Red "Windows Terminal settings file not found: $SettingsPath"
    exit 1
}

$settings = Get-Content -Path $SettingsPath -Raw | ConvertFrom-Json

Write-Title ':: Update Windows Terminal Themes'

$fetchedSchemes = [System.Collections.Generic.List[object]]::new()
$fetchedThemes = [System.Collections.Generic.List[object]]::new()
$hasChanges = $false

foreach ($t in $themes) {
    try {
        $scheme = Invoke-RestMethod -Uri $t.SchemeUrl
        $theme = Invoke-RestMethod -Uri $t.ThemeUrl

        $fetchedSchemes.Add($scheme)
        $fetchedThemes.Add($theme)

        $existingScheme = $settings.schemes | Where-Object { $_.name -eq $scheme.name }
        $existingTheme = $settings.themes  | Where-Object { $_.name -eq $theme.name }

        if ($existingScheme -and $existingTheme -and (Test-JsonEqual $existingScheme $scheme) -and (Test-JsonEqual $existingTheme $theme)) {
            Write-Muted "~ terminal/theme/$($t.Name)"
        }
        elseif ($existingScheme -or $existingTheme) {
            Write-Green "^ terminal/theme/$($t.Name)"
            $hasChanges = $true
        }
        else {
            Write-Green "+ terminal/theme/$($t.Name)"
            $hasChanges = $true
        }
    }
    catch {
        Write-Red "! terminal/theme/$($t.Name)"
    }
}

$settings.schemes = $fetchedSchemes
$settings.themes = $fetchedThemes

if ($hasChanges -or (-not (Test-JsonEqual (Get-Content -Path $SettingsPath -Raw) $settings))) {
    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsPath -Encoding UTF8
}
