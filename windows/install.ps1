# Configure PowerShell preferences
# For more info see https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false


# Utilities
function Refresh-SessionPath {
    <#
    .SYNOPSIS
    Refreshes the current session PATH to reflect any system PATH changes.
    #>
    $env:Path = ([Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
        [Environment]::GetEnvironmentVariable('Path', 'User'))
}

function Install-WinGetPackage {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Id,

        [ValidateSet('user', 'machine')]
        [string] $Scope,

        [string] $Custom,
        [string] $Override
    )

    $wingetArguments = @(
        'install', '--id', $Id, '--exact', '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements'
    )

    if ($Scope) {
        $wingetArguments += @('--scope', $Scope)
        # Note: WinGet defaults to 'user' scope if not specified.
        #       If installer doesn't exist for 'user' scope, falls back to 'machine' scope.
    }
    if ($Custom) {
        $wingetArguments += @('--custom', $Custom)
    }
    if ($Override) {
        $wingetArguments += @('--override', $Override)
    }

    Write-Host "Installing $Id via WinGet..."
    winget @wingetArguments

    # Check if installation was successful
    if ($LASTEXITCODE -notin @(0, -1978335189)) {
        <#
        Exit code 0x8A15002B (hex) / -1978335189 (dec) is also valid since it's returned when the
        package is already installed, so `winget install` tries to update it, but then it realises
        that the package is already up to date and thus doesn't need to be updated. It corresponds
        to the error symbol `APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE` (can verify by running
        `winget error 0x8A15002B`).
        #>
        throw "WinGet failed for $Id (exit code $LASTEXITCODE)."
    }

    # Refresh the session PATH to include any newly installed software, to be able to call any of
    # its binaries to configure said software
    Refresh-SessionPath
}


# Main Code
function Main {
    Refresh-SessionPath

    # Check if WinGet exists
    if (-not (Get-Command winget -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'WinGet is not available. Install App Installer, then run this script again.'
    }

    Write-Host 'Installing WinGet packages...'

    # Zed
    <#
    Currently this package incorrectly only supports (and thus defaults to) the 'machine' scope,
    despite the installer installing the software at a per-user level instead (i.e. it shd be 'user'
    scope). Anyways it still installs fine, just that it might cause issues if you try to upgrade
    versions via WinGet (tbh just let Zed self-update instd).

    For more info see https://github.com/zed-industries/zed/issues/56791.
    #>
    Install-WinGetPackage 'ZedIndustries.Zed'

    # Git for Windows
    <#
    Setting 'machine' scope here technically doesn't matter since the current Git for Windows
    Inno Setup installer doesn't honour the scope passed to it from WinGet, instead it installs
    based on the current user's administrative privileges.

    We set 'machine' scope here just in case the installer changes behaviour in the future. For now
    it just serves to semantically indicate that it'll be installed system-wide (since in theory
    this script shd be run w/ admin privileges).

    For more info see https://github.com/microsoft/winget-pkgs/issues/369735.

    Also, custom additional arguments are passed to the installer via the '-Custom' parameter, to
    override the default installation options and configure stuff like the default branch name to
    use when creating a new repository. The full list of valid installer options that can be used
    to customise Git can be found at https://gitforwindows.org/silent-or-unattended-installation.

    In my case, since I use Zed, and it's not one of the inbuilt options for default editors, I opt
    to configure it via the `git config` command instead, since otherwise using the installer to set
    a custom default editor causes said editor to be configured as the default at the system level
    (i.e. system-wide) instead of the global level (i.e. per-user), which doesn't make sense for Zed
    since it's installed per-user.
    #>
    Install-WinGetPackage 'Git.Git' -Scope 'machine' `
        -Custom (@(
            # Enable additional components which are not part of the installer's defaults, namely
            # creating a Git Bash desktop shortcut, enabling daily Git for Windows update checks,
            # and adding a Git Bash profile to Windows Terminal
            # Default: '/COMPONENTS=ext,ext\shellhere,ext\guihere,gitlfs,assoc,assoc_sh,scalar'
            '/COMPONENTS=icons,icons\desktop,ext,ext\shellhere,ext\guihere,gitlfs,assoc,assoc_sh,autoupdate,windowsterminal,scalar'
            # Set the default branch name for new repositories to 'main'
            '/o:DefaultBranchOption=main'
            # Enable symbolic link sypport
            '/o:EnableSymlinks=Enabled'
        ) -join ' ')
    git config --global user.name 'Christopher Cheng'
    git config --global user.email 'chris@ccjk.dev'
    git config --global core.editor "'$env:LOCALAPPDATA\Programs\Zed\bin\zed' --wait"

    # Tailscale
    Install-WinGetPackage 'Tailscale.Tailscale'
    # TODO: Handle configuration

    # Obsidian
    Install-WinGetPackage 'Obsidian.Obsidian'
    # TODO: Handle configuration

    # Espanso
    Install-WinGetPackage 'Espanso.Espanso'
    # TODO: Handle configuration

    # Steam
    Install-WinGetPackage 'Valve.Steam'

    # mise
    Install-WinGetPackage 'jdx.mise'

    Write-Host 'Configuring mise...'

    # Download custom global mise config
    $miseConfigDirectory = Join-Path $env:USERPROFILE '.config\mise'
    $miseConfigPath = Join-Path $miseConfigDirectory 'config.toml'
    if (Test-Path -LiteralPath $miseConfigPath) {
        $overwrite = Read-Host "$miseConfigPath already exists. Overwrite it? [y/N]"
        if ($overwrite.Trim() -notin @('y', 'yes')) {
            Write-Host 'Keeping the existing global mise config. Stopping the script.'
            return
        }
    }
    New-Item -ItemType Directory -Path $miseConfigDirectory -Force | Out-Null
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/CCJK123/setup-scripts/main/shared/mise.toml' `
        -OutFile $miseConfigPath -UseBasicParsing

    # Apply custom global mise config
    Write-Host "Installing mise tools based on `mise.toml` config..."
    mise --cd $miseConfigDirectory install
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install mise tools (exit code $LASTEXITCODE)."
    }

    # Add mise shim path to both the current user's and the current session's PATH
    # This is so mise tools are still available in non-interactive contexts
    $miseShimPath = Join-Path $env:LOCALAPPDATA 'mise\shims'
    $existingUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($existingUserPath -split ';' | ForEach-Object { $_.TrimEnd('\') }) -notcontains $miseShimPath) {
        [Environment]::SetEnvironmentVariable('Path', "$miseShimPath;$existingUserPath".TrimEnd(';'), 'User')
        Write-Host "Added mise shims to the current user's PATH."
    }
    Refresh-SessionPath

    # TODO: Consider modifying .bashrc or similar files to include `eval "$(mise activate bash)"`

    Write-Host 'Configuring mise tools...'
    mise --cd $miseConfigDirectory env -s powershell |
        Out-String |
        Invoke-Expression
}


# Refresh PATH for this script, then restore the caller's original PATH.
$originalPath = $env:Path
try {
    Main
} finally {
    $env:Path = $originalPath
}
