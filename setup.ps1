[CmdletBinding()]
param(
    [Parameter(HelpMessage = 'URL to hardware-metadata.json')]
    [String] $MetadataUrl = 'https://zmk.dev/hardware-metadata.json'
)

Set-StrictMode -Version 3.0


function Show-Menu {
    param (
        [Parameter(Mandatory)] [string] $Title,
        [Parameter(Mandatory)] [array] $MenuItems,
        [ScriptBlock] $Formatter = { param($x) $x.ToString() },
        [ConsoleColor] $FocusColor = [ConsoleColor]::Green
    )

    # Ref: https://docs.microsoft.com/en-us/windows/desktop/inputdev/virtual-key-codes
    $KeyConstants = [PSCustomObject]@{
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
            [ConsoleColor] $FocusColor
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
            $Text = $Text.Substring(0, $consoleWidth)
        }
        elseif ($Text.Length -lt $consoleWidth) {
            $Text = $Text.PadRight($consoleWidth)
        }

        Write-Host $Text @params
    }

    function Write-Menu {
        param (
            [Parameter(Mandatory)] [string] $Title,
            [Parameter(Mandatory)] [array] $MenuItems,
            [Parameter(Mandatory)] [int] $MenuHeight,
            [Parameter(Mandatory)] [ScriptBlock] $Formatter,
            [Parameter(Mandatory)] [int] $ScrollIndex,
            [Parameter(Mandatory)] [int] $FocusIndex,
            [Parameter(Mandatory)] [ConsoleColor] $FocusColor
        )

        if ($null -ne $Title) {
            Write-Host $Title
        }

        $displayCount = [Math]::Min($MenuItems.Count, $MenuHeight)

        for ($row = 0; $row -lt $displayCount; $row++) {
            $index = $ScrollIndex + $row
            $item = $MenuItems[$index]
            $focused = $index -eq $FocusIndex
            $text = & $Formatter $item

            Write-MenuItem -Text $text -IsFocused:$focused -FocusColor $FocusColor
        }
    }

    try {
        [System.Console]::CursorVisible = $false
        $index = 0
        $scroll = 0

        while ($true) {
            $menuHeight = Get-MenuHeight

            Write-Menu -Title $Title -MenuItems $MenuItems -MenuHeight $menuHeight -ScrollIndex $scroll `
                -FocusIndex $index -FocusColor $FocusColor -Formatter $Formatter

            $vkeyCode = (Read-VKey).VirtualKeyCode

            switch ($vkeyCode) {
                $KeyConstants.VK_UP { $index-- }
                $KeyConstants.VK_DOWN { $index++ }
                $KeyConstants.VK_PRIOR { $index -= $menuHeight }
                $KeyConstants.VK_NEXT { $index += $menuHeight }
                $KeyConstants.VK_HOME { $index = 0 }
                $KeyConstants.VK_END { $index = $MenuItems.Count - 1 }

                $KeyConstants.VK_ESCAPE { return $null }
                $KeyConstants.VK_RETURN { return $MenuItems[$index] }
                # Ctrl+C returns 0
                0 { return $null }
            }

            $index = [Math]::Clamp($index, 0, $MenuItems.Count - 1)
            $scroll = Get-NewScrollIndex -MenuItems $MenuItems -MenuHeight $menuHeight -ScrollIndex $scroll -FocusIndex $index

            $menuStartRow = Get-MenuStartRow -MenuItems $MenuItems -MenuHeight $menuHeight

            [System.Console]::SetCursorPosition(0, [Math]::Max(0, $menuStartRow))
        }
    }
    finally {
        [System.Console]::CursorVisible = $true
    }
}


function Get-Resource {
    param(
        [string]
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $Uri
    )

    if ($Uri -match '^.*://') {
        return (New-Object System.Net.WebClient).DownloadString($Uri)
    }
    return Get-Content -Path $Uri
}

function Get-IsKeyboard {
    param (
        [Parameter(Mandatory)] [PSCustomObject] $Hardware
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
        [Parameter(Mandatory)] [PSCustomObject] $Hardware
    )

    return ($Hardware.type -eq 'board') -and -not (Get-IsKeyboard $Hardware)
}


function Get-InterconnectCompatible {
    param (
        [Parameter(Mandatory)] [PSCustomObject] $Shield,
        [Parameter(Mandatory)] [PSCustomObject] $Board
    )

    $requirements = $Shield.requires | ForEach-Object { $Board.exposes -Contains $_ }
    return $requirements -NotContains $false
}

function Get-SiblingIds {
    param (
        [Parameter(Mandatory)] [PSCustomObject] $Hardware
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
        [Parameter(Mandatory)] [PSCustomObject] $Hardware
    )

    return (Get-SiblingIds $Hardware) -gt 1
}


function Get-IsUsbOnly {
    param (
        [Parameter(Mandatory)] [PSCustomObject] $Hardware
    )

    try {
        return $Hardware.outputs -NotContains 'ble'
    }
    catch {
        return $false
    }
}

$hardware = Get-Resource $MetadataUrl | ConvertFrom-Json
$boardIds = @()
$shieldIds = @()

$keyboards = $hardware | Where-Object { Get-IsKeyboard $_ } | Sort-Object -Property name
$keyboard = Show-Menu -Title 'Pick a keyboard:' -MenuItems $keyboards -Formatter { $Args | Select-Object -ExpandProperty name }

if ($null -eq $keyboard) {
    Write-Host 'Canceled.'
    exit 1
}

if ($keyboard.type -eq 'board') {
    $boardIds = Get-SiblingIds $keyboard
}
else {
    $controllers = $Hardware | Where-Object { (Get-IsController $_) -and (Get-InterconnectCompatible -Shield $keyboard -Board $_) } | Sort-Object -Property name
    $controller = Show-Menu -Title 'Pick an MCU board:' -MenuItems $controllers -Formatter { $Args | Select-Object -ExpandProperty name }

    if ($null -eq $controller) {
        Write-Host 'Canceled.'
        exit 1
    }

    if ((Get-IsSplit $keyboard) -and (Get-IsUsbOnly $controller)) {
        Write-Host 'Wired split is not yet supported by ZMK.'
        exit 1
    }

    $boardIds = @($controller.id)
    $shieldIds = Get-SiblingIds $keyboard
}

Write-Host
Write-Host 'Selected boards'
Write-Host $boardIds
Write-Host
Write-Host 'Selected shields'
Write-Host $shieldIds
