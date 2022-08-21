# Copyright (c) 2022 The ZMK Contributors
# SPDX-License-Identifier: MIT

<#
    .SYNOPSIS
    Adds a keyboard to a ZMK user config repo.

    .DESCRIPTION
    This script allows you to select from any of the keyboards supported by
    ZMK and add it to a user config repo.

    If the script is run from a folder containing an existing ZMK user config
    repo, it can edit that repo. Otherwise, it will prompt for a repo to clone.

    .LINK
    https://zmk.dev/docs/user-setup
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    # URL to hardware-metadata.json.
    [string] $MetadataUrl = 'https://zmk.dev/hardware-metadata.json',

    # URL to the template repo.
    [string] $TemplateUrl = 'https://github.com/zmkfirmware/unified-zmk-config-template.git',

    # Base URL to download files.
    [string] $FilesUrl = 'https://raw.githubusercontent.com/zmkfirmware/zmk/main'
)

Set-StrictMode -Version 3.0


function Test-Git-Config {
    <#
    .SYNOPSIS
    Prints an error message and exits if the given Git config option is not set.
    #>
    param (
        [Parameter(Mandatory)] [string] $Option,
        [Parameter(Mandatory)] [string] $ErrorMessage
    )

    git config $Option | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host $ErrorMessage
        exit 1
    }

}

# Based on https://github.com/Sebazzz/PSMenu
# MIT License https://github.com/Sebazzz/PSMenu/blob/master/LICENSE
function Show-Menu {
    <#
    .SYNOPSIS
    Shows a list of menu options and returns the chosen option.

    .OUTPUTS
    The selected item from -MenuItems. If the user cancels with Escape or Ctrl+C,
    the script is terminated and no value is returned.
    #>
    [CmdletBinding()]
    param (
        # Prompt to display at the top of the menu.
        [Parameter(Mandatory)] [string] $Title,
        # List of objects to use as menu items.
        [Parameter(Mandatory)] [array] $MenuItems,
        # Script block which takes a menu item object and returns the string to display.
        [scriptblock] $Formatter = { param($x) $x.ToString() },
        # Highlight color for the selected menu item.
        [System.ConsoleColor] $FocusColor = [System.ConsoleColor]::Green,
        # Index of the initially-selected menu item.
        [int] $DefaultIndex = 0
    )

    # Ref: https://docs.microsoft.com/en-us/windows/desktop/inputdev/virtual-key-codes
    $KeyConstants = [pscustomobject]@{
        VK_RETURN = 0x0D;
        VK_ESCAPE = 0x1B;
        VK_UP     = 0x26;
        VK_DOWN   = 0x28;
        VK_PRIOR  = 0x21;
        VK_NEXT   = 0x22;
        VK_END    = 0x23;
        VK_HOME   = 0x24;
    }

    function Read-VKey {
        return $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }

    function Get-MenuHeight() {
        $ExtraLines = 3 # console prompt + title line + empty line at end
        return $Host.UI.RawUI.WindowSize.Height - $ExtraLines
    }

    function Get-DisplayCount() {
        param (
            [Parameter(Mandatory)] [array] $MenuItems,
            [Parameter(Mandatory)] [int] $MenuHeight
        )

        return [Math]::Min($MenuItems.Count, $MenuHeight)
    }

    function Get-MenuStartRow() {
        param (
            [Parameter(Mandatory)] [array] $MenuItems,
            [Parameter(Mandatory)] [int] $MenuHeight
        )
        $displayCount = Get-DisplayCount -MenuItems $MenuItems -MenuHeight $MenuHeight
        return [Console]::CursorTop - $displayCount - 1
    }

    function Get-NewScrollIndex {
        param (
            [Parameter(Mandatory)] [array] $MenuItems,
            [Parameter(Mandatory)] [int] $MenuHeight,
            [Parameter(Mandatory)] [int] $ScrollIndex,
            [Parameter(Mandatory)] [int] $FocusIndex
        )

        $displayCount = Get-DisplayCount -MenuItems $MenuItems -MenuHeight $MenuHeight

        if ($MenuItems.Count -le $displayCount) {
            return 0
        }

        $firstDisplayed = $ScrollIndex
        $lastDisplayed = $firstDisplayed + $displayCount - 1

        if ($FocusIndex -le $firstDisplayed) {
            return [Math]::Max(0, $FocusIndex - 1)
        }

        if ($FocusIndex -ge $lastDisplayed) {
            return [Math]::Min($MenuItems.Count - 1, $FocusIndex + 1) - ($displayCount - 1)
        }

        return $ScrollIndex
    }

    function Write-MenuItem {
        param (
            [Parameter(Mandatory)] [string] $Text,
            [switch] $IsFocused,
            [System.ConsoleColor] $FocusColor
        )

        $consoleWidth = [Console]::BufferWidth
        $params = @{}

        if ($IsFocused) {
            $params.ForegroundColor = $FocusColor
            $Text = "> $Text"
        }
        else {
            $Text = "  $Text"
        }

        if ($Text.Length -gt $consoleWidth) {
            # Menu items are assumed to be one line each, so truncate if needed.
            $Text = $Text.Substring(0, $consoleWidth)
        }
        elseif ($Text.Length -lt $consoleWidth) {
            # Clear the rest of the line to hide leftover text from other menu items when scrolling.
            $Text = $Text.PadRight($consoleWidth)
        }

        Write-Host $Text @params
    }

    function Write-Menu {
        param (
            [Parameter(Mandatory)] [string] $Title,
            [Parameter(Mandatory)] [array] $MenuItems,
            [Parameter(Mandatory)] [int] $MenuHeight,
            [Parameter(Mandatory)] [scriptblock] $Formatter,
            [Parameter(Mandatory)] [int] $ScrollIndex,
            [Parameter(Mandatory)] [int] $FocusIndex,
            [Parameter(Mandatory)] [System.ConsoleColor] $FocusColor
        )

        if ($null -ne $Title) {
            Write-Host $Title
        }

        $displayCount = [Math]::Min($MenuItems.Count, $MenuHeight)

        for ($row = 0; $row -lt $displayCount; $row++) {
            $index = $ScrollIndex + $row
            $text = & $Formatter $MenuItems[$index]

            Write-MenuItem -Text $text -IsFocused:($index -eq $FocusIndex) -FocusColor $FocusColor
        }
    }

    try {
        # The cursor will be hidden on the last line of the console.
        [System.Console]::CursorVisible = $false

        $menuHeight = Get-MenuHeight

        $index = $DefaultIndex
        $scroll = Get-NewScrollIndex -MenuItems $MenuItems -MenuHeight $menuHeight -ScrollIndex 0 -FocusIndex $index

        while ($true) {
            $menuHeight = Get-MenuHeight
            $itemsAndHeight = @{
                MenuItems  = $MenuItems
                MenuHeight = $menuHeight
            }

            Write-Menu -Title $Title @itemsAndHeight -ScrollIndex $scroll -FocusIndex $index `
                -FocusColor $FocusColor -Formatter $Formatter

            $vkeyCode = (Read-VKey).VirtualKeyCode
            switch ($vkeyCode) {
                $KeyConstants.VK_UP { $index-- }
                $KeyConstants.VK_DOWN { $index++ }
                $KeyConstants.VK_PRIOR { $index -= $menuHeight }
                $KeyConstants.VK_NEXT { $index += $menuHeight }
                $KeyConstants.VK_HOME { $index = 0 }
                $KeyConstants.VK_END { $index = $MenuItems.Count - 1 }

                $KeyConstants.VK_RETURN { return $MenuItems[$index] }
                $KeyConstants.VK_ESCAPE { exit 1 }
                0 { exit 1 } # Ctrl+C returns 0
            }

            # Clamp the focused index to within the menu and scroll if needed to keep it on screen.
            $index = [Math]::Min([Math]::Max($index, 0), $MenuItems.Count - 1)
            $scroll = Get-NewScrollIndex @itemsAndHeight -ScrollIndex $scroll -FocusIndex $index

            # Move the cursor back to the top of the menu so we can overwrite the entire menu.
            $menuStartRow = Get-MenuStartRow @itemsAndHeight
            [System.Console]::SetCursorPosition(0, [Math]::Max(0, $menuStartRow))
        }
    }
    finally {
        [System.Console]::CursorVisible = $true
        Write-Host
    }
}

function Show-YesNoPrompt {
    <#
    .SYNOPSIS
    Displays a menu with Yes/No options.

    .OUTPUTS
    Returns $true if the user selected "Yes" or $false otherwise.
    #>
    param (
        # Prompt to display at the top of the menu.
        [Parameter(Mandatory)] [string] $Title,
        # Select "No" by default.
        [switch] $DefaultNo
    )

    $result = Show-Menu -Title $Title -MenuItems 'Yes', 'No' -Default $(if ($DefaultNo) { 1 } else { 0 })

    return $result -eq 'Yes'
}


function Get-Resource {
    <#
    .SYNOPSIS
    Gets the contents of a text file as a string.
    #>
    param(
        # URL or local path of the file to get.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Uri
    )

    if ($Uri -match '^.*://') {
        return (New-Object System.Net.WebClient).DownloadString($Uri)
    }
    return Get-Content -Path $Uri
}


function Get-IsKeyboard {
    param (
        [Parameter(Mandatory)] [pscustomobject] $Hardware
    )

    switch ($Hardware.type) {
        'board' {
            try {
                return $Hardware.features -Contains 'keys'
            }
            catch {
                return $false
            }
        }
        'shield' { return $true }
        default { return $false }
    }
}


function Get-IsController {
    param (
        [Parameter(Mandatory)] [pscustomobject] $Hardware
    )

    return ($Hardware.type -eq 'board') -and -not (Get-IsKeyboard $Hardware)
}


function Get-IsInterconnectCompatible {
    param (
        [Parameter(Mandatory)] [pscustomobject] $Shield,
        [Parameter(Mandatory)] [pscustomobject] $Board
    )

    $requirements = $Shield.requires | ForEach-Object { $Board.exposes -Contains $_ }
    return $requirements -NotContains $false
}


function Get-IsCompatibleController {
    param (
        [Parameter(Mandatory)] [pscustomobject] $Shield,
        [Parameter(Mandatory)] [pscustomobject] $Board
    )

    return (Get-IsController $Board) -and (Get-IsInterconnectCompatible -Shield $Shield -Board $Board)
}


function Get-SiblingIds {
    param (
        [Parameter(Mandatory)] [pscustomobject] $Hardware
    )

    try {
        return $Hardware.siblings
    }
    catch {
        return @($Hardware.id)
    }
}


function Get-IsSplit {
    param (
        [Parameter(Mandatory)] [pscustomobject] $Hardware
    )

    return (Get-SiblingIds $Hardware) -gt 1
}


function Get-IsUsbOnly {
    param (
        [Parameter(Mandatory)] [pscustomobject] $Hardware
    )

    return $Hardware.outputs -NotContains 'ble'
}

function Add-ContentIfNotExists {
    <#
    .SYNOPSIS
    Adds text to a file if there is no line (or sequence of lines) in the file
    that matches that text.
    #>
    param (
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Value
    )

    $escaped = [Regex]::Escape($Value).Replace('`n', '\s*\n\s*')
    $regex = "(?m)^\s*$escaped\s*$"

    if ((Get-Content -Path $Path -Raw) -notmatch $regex) {
        Add-Content -Path $Path -Value $Value
    }
}

function Add-BuildMatrix {
    <#
    .SYNOPSIS
    Adds a list of board IDs and optionally shield IDs to the build matrix.
    One build is added per combination of board and shield.
    #>
    param (
        [Parameter(Mandatory)] [array] $BoardIds,
        [array] $ShieldIds = @(),
        [string] $Path = 'build.yaml'
    )

    # Make sure file ends with a trailing newline so we don't append to an existing line
    if ((Get-Content -Path $Path -Raw) -notmatch '(?<=\n)$') {
        Add-Content -Path $Path -Value ''
    }

    Add-ContentIfNotExists -Path $Path -Value 'include:'

    foreach ($board in $BoardIds) {
        if ($ShieldIds) {
            foreach ($shield in $ShieldIds) {
                Add-ContentIfNotExists -Path $Path -Value "  - shield: $shield`n    board: $board"
            }
        }
        else {
            Add-ContentIfNotExists -Path $Path -Value "  - board: $board"
        }
    }
}


# Test for dependencies
try {
    git | Out-Null
}
catch [System.Management.Automation.CommandNotFoundException] {
    Write-Host 'This script requires Git. Please install it from https://git-scm.com/downloads'
    exit 1
}

Test-Git-Config -Option 'user.name' -ErrorMessage "Git username not set!`nRun: git config --global user.name 'My Name'"
Test-Git-Config -Option 'user.email' -ErrorMessage "Git email not set!`nRun: git config --global user.email 'example@myemail.com'"

# Select the repo to modify
$repoPath = $null

if (Test-Path -Path '.git') {
    Write-Host
    Write-Host "Found an existing Git repo at $(Get-Location)"
    Write-Host

    $edit = 'Edit this repo'
    $clone = 'Clone a new repo here'
    $cancel = 'Cancel'

    $response = Show-Menu -Title 'Select an option:' -MenuItems $edit, $clone, $cancel

    switch ($response) {
        $edit { $repoPath = Get-Location }
        $clone { $repoPath = $null }
        default { exit 1 }
    }
}

if ($null -eq $repoPath) {
    Write-Host 'This script must clone your user config repo locally for modifications.'
    Write-Host '(If you have done this already, press Ctrl+C to cancel and re-run the'
    Write-Host 'script from the repo folder.)'
    Write-Host
    Write-Host 'If you do not have a user config repo, please sign in to https://github.com,'
    Write-Host 'open the following URL, click the "Use this template" button, and follow the'
    Write-Host 'instructions to create your repo.'
    Write-Host
    Write-Host "    $($TemplateUrl.Replace('.git', ''))"
    Write-Host
    Write-Host 'Next, go to your repo page on GitHub and click the "Code" button. Copy the repo'
    Write-Host 'URL and paste it here (Ctrl+Shift+V or right click).'
    Write-Host

    $repoUrl = Read-Host 'Repo URL'
    Write-Host

    if (!$repoUrl) {
        Write-Host 'Canceled.'
        exit 1
    }

    $repoName = $repoUrl.Replace('.git', '').Split('/')[-1]

    git clone --single-branch "$repoUrl" "$repoName"
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Clone failed.'
        exit 1
    }

    $repoPath = $repoName
}

# Repo selected. Switch to it and make sure we have the latest changes.
Set-Location $repoPath

if (git status --porcelain) {
    Write-Host 'You have local changes in this repo. Please commit or stash them first.' -ForegroundColor Yellow
    exit 1
}

$repoUrl = $(git remote get-url $(git remote))
$actionsUrl = $null
if ($repoUrl.StartsWith('https://github.com')) {
    $actionsUrl = "$($repoUrl.Replace('.git', ''))/actions"
}

git pull

# Ensure all the necessary files are here. If not, ask to copy them from the template.
$actionsYaml = '.github/workflows/build.yml'
$westYaml = 'config/west.yml'
$buildYaml = 'build.yaml'

$actionsYamlExists = Test-Path -Path $actionsYaml
$westYamlExists = Test-Path -Path $westYaml
$buildYamlExists = Test-Path -Path $buildYaml

if (!$actionsYamlExists -or !$westYamlExists -or !$buildYamlExists) {
    Write-Host
    Write-Host 'The following required files are missing:' -ForegroundColor Yellow
    if (!$actionsYamlExists) { Write-Host "- $actionsYaml" -ForegroundColor Yellow }
    if (!$westYamlExists) { Write-Host "- $westYaml" -ForegroundColor Yellow }
    if (!$buildYamlExists) { Write-Host "- $buildYaml" -ForegroundColor Yellow }

    Write-Host
    if (!(Show-YesNoPrompt -Title 'Initialize these files?')) {
        Write-Host 'Canceled.'
        exit 1
    }

    git fetch $TemplateUrl

    if (!$actionsYamlExists) { git checkout FETCH_HEAD -- $actionsYaml }
    if (!$westYamlExists) { git checkout FETCH_HEAD -- $westYaml }
    if (!$buildYamlExists) { git checkout FETCH_HEAD -- $buildYaml }

    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Failed to initialize repo.' -ForegroundColor Yellow
        exit 1
    }

    git add .
    git commit -m 'Initialize repo from template'
}

# Prompt user for keyboard options

Write-Host 'Fetching keyboard list...'
$hardware = Get-Resource $MetadataUrl | ConvertFrom-Json
$boardIds = @()
$shieldIds = @()

$keyboards = $hardware |
    Where-Object { Get-IsKeyboard $_ } |
    Sort-Object -Property name

$formatHardware = { param($x) $x.name }

Write-Host
$keyboard = Show-Menu -Title 'Pick a keyboard:' -MenuItems $keyboards -Formatter $formatHardware

if ($keyboard.type -eq 'board') {
    $boardIds = Get-SiblingIds $keyboard
}
else {
    $controllers = $Hardware |
        Where-Object { Get-IsCompatibleController -Shield $keyboard -Board $_ } |
        Sort-Object -Property name

    $controller = Show-Menu -Title 'Pick an MCU board:' -MenuItems $controllers -Formatter $formatHardware

    if ((Get-IsSplit $keyboard) -and (Get-IsUsbOnly $controller)) {
        Write-Host 'Sorry, wired split is not yet supported by ZMK.' -ForegroundColor Yellow
        exit 1
    }

    $boardIds = @($controller.id)
    $shieldIds = Get-SiblingIds $keyboard
}

$copyKeymap = Show-YesNoPrompt -Title 'Copy the stock keymap for customization?'

# Confirm user wants to apply changes

Write-Host 'Adding the following to your user config repo:'
if ($shieldIds) {
    Write-Host "- MCU Board:    $($controller.name)" -NoNewline
    Write-Host "  ($boardIds)" -ForegroundColor Black
    Write-Host "- Shield:       $($keyboard.name)" -NoNewline
    Write-Host "  ($shieldIds)" -ForegroundColor Black
}
else {
    Write-Host "- Board:        $($keyboard.name)  `e[90m($boardIds)"
}
Write-Host "- Copy keymap?: $(if ($copyKeymap) {'Yes'} else {'No'})"
Write-Host "- Repo URL:     $repoUrl"
Write-Host
if (!(Show-YesNoPrompt -Title 'Continue?')) {
    Write-Host 'Canceled.'
    exit 1
}

# Apply changes

$configName = "$($keyboard.id).conf"
$configUrl = "$FilesUrl/$($keyboard.directory)/$configName"
$configPath = "config/$configName"

$keymapName = "$($keyboard.id).keymap"
$keymapUrl = "$FilesUrl/$($keyboard.directory)/$keymapName"
$keymapPath = "config/$keymapName"

if (Test-Path -Path $configPath) {
    Write-Host "$configPath already exists."
}
else {
    try {
        Write-Host "Downloading config file ($configUrl)"
        Invoke-RestMethod -Uri $configUrl -OutFile $configPath
    }
    catch {
        Set-Content -Path $configPath '# Place configuration items here'
    }
}

if ($copyKeymap) {
    if (Test-Path -Path $keymapPath) {
        Write-Host "$keymapPath already exists."
    }
    else {
        try {
            Write-Host "Downloading keymap file ($keymapUrl)"
            Invoke-RestMethod -Uri $keymapUrl -OutFile $keymapPath
        }
        catch {
            Write-Host 'Failed to download keymap'
        }
    }
}

Write-Host 'Updating build matrix...'
Add-BuildMatrix -BoardIds $boardIds -ShieldIds $shieldIds

Write-Host 'Committing changes...'
Write-Host

git add .
git commit -m "Add $($keyboard.name)"

Write-Host
Write-Host "Pushing changes to $repoUrl ..."
Write-Host

git push --set-upstream origin $(git symbolic-ref --short HEAD)

if ($LASTEXITCODE -ne 0) {
    Write-Host
    Write-Host "Failed to push to $repoUrl" -ForegroundColor Red
    Write-Host "Check your repo's URL and try again by running the following commands:"
    Write-Host '    git remote rm origin'
    Write-Host '    git remote add origin <PASTE_REPO_URL_HERE>'
    Write-Host "    git push --set-upstream origin $(git symbolic-ref --short HEAD)"
    exit 1
}

if ($actionsUrl) {
    Write-Host
    Write-Host 'Success! Your firmware will be available from GitHub Actions at:' -ForegroundColor Green
    Write-Host
    Write-Host "    $actionsUrl"
    Write-Host
}
