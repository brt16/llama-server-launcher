@echo off
setlocal
title llama-server-launcher
echo Starting GUI, please wait...
set "_ps=%TEMP%\llm-gui-%RANDOM%-%RANDOM%.ps1"
powershell -ExecutionPolicy Bypass -NoProfile -Command "$bat='%~f0'; $marker='#' + 'PSSTART'; $content=[System.IO.File]::ReadAllText($bat); $index=$content.LastIndexOf($marker); if ($index -lt 0) { throw 'Embedded script marker not found.' }; [System.IO.File]::WriteAllText('%_ps%', $content.Substring($index + $marker.Length))"
if errorlevel 1 (
    echo.
    echo [ERROR] Failed to extract embedded PowerShell from the launcher.
    pause
    del "%_ps%" 2>nul
    endlocal
    exit /b 1
)

powershell -ExecutionPolicy Bypass -NoProfile -File "%_ps%" -BatPath "%~f0"
set "_ec=%errorlevel%"
if not "%_ec%"=="0" (
    echo.
    echo [ERROR] The launcher failed. Review the details above and copy them if needed.
    pause
)
del "%_ps%" 2>nul
endlocal
exit /b %_ec%
#PSSTART
param(
    [string]$BatPath
)

try {
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
$script:CpuCores = [Environment]::ProcessorCount
$script:BatDir = if ($BatPath) { Split-Path -Parent $BatPath } else { (Get-Location).Path }
$script:OptionCatalog = [System.Collections.ArrayList]::new()
$script:OptionStates = [System.Collections.ArrayList]::new()
$script:OptionStatesById = @{}
$script:TabPages = @{}
$script:TabTitles = @{}
$script:TabLayouts = @{}
$script:TabOrder = [System.Collections.ArrayList]::new()
$script:SectionLabels = [System.Collections.ArrayList]::new()
$script:AllOptionsList = $null
$script:AllOptionsSearch = $null
$script:txtServer = $null
$script:txtModel = $null
$script:txtToolWorkingDir = $null
$script:txtPreview = $null
$script:cmbMode = $null
$script:cmbView = $null
$script:lblModeHint = $null
$script:lblModel = $null
$script:lblModeRequired = $null
$script:lblViewRequired = $null
$script:form = $null
$script:titleLabel = $null
$script:subtitleLabel = $null
$script:grpRequired = $null
$script:lblServerRequired = $null
$script:lblToolWorkingDir = $null
$script:btnServer = $null
$script:btnModel = $null
$script:btnToolWorkingDir = $null
$script:mainSplit = $null
$script:previewLabel = $null
$script:btnCopy = $null
$script:btnReset = $null
$script:btnLaunch = $null

function New-Choice {
    param(
        [string]$Label,
        [string]$Flag
    )

    [PSCustomObject]@{
        Label = $Label
        Flag  = $Flag
    }
}

function New-OptionMeta {
    param(
        [string]$Id,
        [string]$Tab,
        [string]$Section,
        [string]$Label,
        [string]$Type,
        [string]$Flag = '',
        [string]$Tooltip = '',
        $Default = $null,
        $Choices = $null,
        $Min = $null,
        $Max = $null,
        $Increment = $null,
        [int]$Decimals = 0,
        [string]$NegFlag = '',
        [string]$BrowseMode = '',
        [string]$Filter = 'All files (*.*)|*.*',
        [bool]$Editable = $false,
        [bool]$Basic = $false,
        [string]$DisplayFlag = ''
    )

    if (-not $DisplayFlag) {
        if ($Type -eq 'pair' -and $NegFlag) {
            $DisplayFlag = "$Flag / $NegFlag"
        } elseif ($Type -eq 'flagchoice' -and $Choices) {
            $DisplayFlag = (($Choices | ForEach-Object { $_.Flag }) -join ', ')
        } else {
            $DisplayFlag = $Flag
        }
    }

    [PSCustomObject]@{
        Id          = $Id
        Tab         = $Tab
        Section     = $Section
        Label       = $Label
        Type        = $Type
        Flag        = $Flag
        NegFlag     = $NegFlag
        Tooltip     = $Tooltip
        Default     = $Default
        Choices     = $Choices
        Min         = $Min
        Max         = $Max
        Increment   = $Increment
        Decimals    = $Decimals
        BrowseMode  = $BrowseMode
        Filter      = $Filter
        Editable    = $Editable
        Basic       = $Basic
        DisplayFlag = $DisplayFlag
    }
}

function Add-OptionMeta {
    param(
        [Parameter(Mandatory = $true)]
        $Option
    )

    [void]$script:OptionCatalog.Add($Option)
}

function Repeat-Char {
    param(
        [char]$Character,
        [int]$Count
    )

    if ($Count -le 0) { return '' }
    return New-Object string($Character, $Count)
}

function Quote-WindowsArgument {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) { return '""' }
    if ($Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0

    foreach ($char in $Value.ToCharArray()) {
        if ($char -eq '\') {
            $backslashes++
            continue
        }

        if ($char -eq '"') {
            [void]$builder.Append((Repeat-Char '\' ($backslashes * 2 + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }

        if ($backslashes -gt 0) {
            [void]$builder.Append((Repeat-Char '\' $backslashes))
            $backslashes = 0
        }

        [void]$builder.Append($char)
    }

    if ($backslashes -gt 0) {
        [void]$builder.Append((Repeat-Char '\' ($backslashes * 2)))
    }

    [void]$builder.Append('"')
    return $builder.ToString()
}

function Browse-Path {
    param(
        [string]$Title,
        [string]$Mode,
        [string]$Filter,
        [string]$StartDir
    )

    if ($Mode -eq 'folder') {
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = $Title
        if ($StartDir -and (Test-Path $StartDir)) {
            $dialog.SelectedPath = $StartDir
        }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
        return $null
    }

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = $Title
    $dialog.Filter = $Filter
    if ($StartDir -and (Test-Path $StartDir)) {
        $dialog.InitialDirectory = $StartDir
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}

function Get-TabDisplayTitle {
    param([string]$TabKey)
    return $script:TabTitles[$TabKey]
}

function Format-OptionValueForStatus {
    param(
        [Parameter(Mandatory = $true)]
        $State
    )

    $meta = $State.Meta
    switch ($meta.Type) {
        'flag' { return 'On' }
        'pair' { return [string]$State.Control.SelectedItem }
        'combo' { return [string]$State.Control.Text }
        'flagchoice' {
            $selected = [string]$State.Control.SelectedItem
            if ($selected) { return $selected }
            return 'Selected'
        }
        'number' {
            return ([decimal]$State.Control.Value).ToString($script:InvariantCulture)
        }
        'decimal' {
            return ([decimal]$State.Control.Value).ToString($script:InvariantCulture)
        }
        default {
            if ($State.Control -and -not [string]::IsNullOrWhiteSpace($State.Control.Text)) {
                return $State.Control.Text
            }
            return 'Checked'
        }
    }
}

function Get-OptionTokens {
    param(
        [Parameter(Mandatory = $true)]
        $State
    )

    $meta = $State.Meta
    $tokens = New-Object System.Collections.Generic.List[string]

    if (-not $State.Override.Checked) {
        return $tokens
    }

    switch ($meta.Type) {
        'flag' {
            [void]$tokens.Add($meta.Flag)
        }
        'pair' {
            if ([string]$State.Control.SelectedItem -eq 'Disabled') {
                [void]$tokens.Add($meta.NegFlag)
            } else {
                [void]$tokens.Add($meta.Flag)
            }
        }
        'combo' {
            $value = [string]$State.Control.Text
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                [void]$tokens.Add($meta.Flag)
                [void]$tokens.Add($value)
            }
        }
        'number' {
            [void]$tokens.Add($meta.Flag)
            [void]$tokens.Add(([decimal]$State.Control.Value).ToString($script:InvariantCulture))
        }
        'decimal' {
            [void]$tokens.Add($meta.Flag)
            [void]$tokens.Add(([decimal]$State.Control.Value).ToString($script:InvariantCulture))
        }
        'flagchoice' {
            $label = [string]$State.Control.SelectedItem
            if (-not [string]::IsNullOrWhiteSpace($label)) {
                $choice = $meta.Choices | Where-Object { $_.Label -eq $label } | Select-Object -First 1
                if ($choice) {
                    [void]$tokens.Add($choice.Flag)
                }
            }
        }
        default {
            if (-not [string]::IsNullOrWhiteSpace($State.Control.Text)) {
                [void]$tokens.Add($meta.Flag)
                [void]$tokens.Add($State.Control.Text)
            }
        }
    }

    return $tokens
}

function Get-ArgumentTokens {
    $tokens = New-Object System.Collections.Generic.List[string]

    if ($script:txtModel.Text) {
        [void]$tokens.Add('--model')
        [void]$tokens.Add($script:txtModel.Text)
    }

    foreach ($state in $script:OptionStates) {
        $stateTokens = Get-OptionTokens -State $state
        foreach ($token in $stateTokens) {
            [void]$tokens.Add($token)
        }
    }

    return $tokens
}

function Get-FlatCommandText {
    $parts = New-Object System.Collections.Generic.List[string]
    [void]$parts.Add((Quote-WindowsArgument $script:txtServer.Text))
    foreach ($token in (Get-ArgumentTokens)) {
        [void]$parts.Add((Quote-WindowsArgument $token))
    }
    return ($parts -join ' ')
}

function Refresh-AllOptionsList {
    if (-not $script:AllOptionsList) { return }

    $query = ''
    if ($script:AllOptionsSearch) {
        $query = $script:AllOptionsSearch.Text.Trim().ToLowerInvariant()
    }

    $script:AllOptionsList.BeginUpdate()
    $script:AllOptionsList.Items.Clear()

    foreach ($state in $script:OptionStates) {
        $searchText = @(
            $state.Meta.Label
            $state.Meta.DisplayFlag
            $state.Meta.Tab
            $state.Meta.Section
            $state.Meta.Tooltip
        ) -join ' '

        if ($query -and $searchText.ToLowerInvariant() -notlike "*$query*") {
            continue
        }

        $status = if ($state.Override.Checked) {
            Format-OptionValueForStatus -State $state
        } else {
            'Default'
        }

        $item = New-Object System.Windows.Forms.ListViewItem($state.Meta.Label)
        [void]$item.SubItems.Add($state.Meta.DisplayFlag)
        [void]$item.SubItems.Add((Get-TabDisplayTitle $state.Meta.Tab))
        [void]$item.SubItems.Add($status)
        $item.Tag = $state
        [void]$script:AllOptionsList.Items.Add($item)
    }

    $script:AllOptionsList.EndUpdate()
}

function Refresh-Preview {
    if (-not $script:txtPreview) { return }

    $exe = Quote-WindowsArgument $script:txtServer.Text
    $argLines = @()
    foreach ($token in (Get-ArgumentTokens)) {
        $argLines += (Quote-WindowsArgument $token)
    }

    if ($argLines.Count -gt 0) {
        $script:txtPreview.Text = $exe + " `r`n    " + ($argLines -join " `r`n    ")
    } else {
        $script:txtPreview.Text = $exe
    }

    Refresh-AllOptionsList
}

function Get-ViewMode {
    if (-not $script:cmbView) {
        return 'Full'
    }

    $view = [string]$script:cmbView.SelectedItem
    if ($view -eq 'Full') {
        return 'Full'
    }

    return 'Basic'
}

function Update-ModeHint {
    $mode = [string]$script:cmbMode.SelectedItem
    $view = & ${function:Get-ViewMode}

    if ($mode -eq 'Router' -and $view -eq 'Basic') {
        $script:lblModeHint.Text = 'Router mode in Basic view keeps the common router controls visible. Full still contains the complete llama-server surface.'
        $script:lblModel.Text = 'Model (.gguf, optional)'
    } elseif ($mode -eq 'Router') {
        $script:lblModeHint.Text = 'Router mode allows model-less launch paths when router sources such as --models-dir or --models-preset are used.'
        $script:lblModel.Text = 'Model (.gguf, optional)'
    } elseif ($view -eq 'Basic') {
        $script:lblModeHint.Text = 'Basic view keeps the common starter settings visible. Leave rows unchecked to stay close to the bare llama-server command.'
        $script:lblModel.Text = 'Model (.gguf)'
    } else {
        $script:lblModeHint.Text = 'Single Model mode keeps the simple path: pick llama-server, pick a model, and Start. Alternative model sources work when checked.'
        $script:lblModel.Text = 'Model (.gguf)'
    }
}

function Get-ViewTabTitle {
    param(
        [string]$TabKey,
        [string]$View
    )

    if ($View -ne 'Basic') {
        return $script:TabTitles[$TabKey]
    }

    switch ($TabKey) {
        'Server'      { return 'Connection' }
        'Model'       { return 'Model' }
        'Performance' { return 'Hardware' }
        'Sampling'    { return 'Generation' }
        'Chat'        { return 'Templates' }
        'Multimodal'  { return 'Vision' }
        'Router'      { return 'Router' }
        default       { return $script:TabTitles[$TabKey] }
    }
}

function Get-ViewSectionTitle {
    param(
        [Parameter(Mandatory = $true)]
        $Meta,
        [string]$View
    )

    if ($View -ne 'Basic') {
        return $Meta.Section
    }

    switch ($Meta.Tab) {
        'Server' {
            switch ($Meta.Section) {
                'Network'                { return 'Server Address' }
                'Authentication and TLS' { return 'Security' }
            }
        }
        'Model' {
            switch ($Meta.Section) {
                'Alternative Model Sources' { return 'Hugging Face & Remote Downloads' }
            }
        }
        'Performance' {
            switch ($Meta.Section) {
                'CPU and Threading'            { return 'CPU & Throughput' }
                'Context and Memory'           { return 'Context Window' }
                'Memory Mapping and KV Cache'  { return 'Memory & KV Cache' }
                'Devices and Offload'          { return 'GPU Offload' }
            }
        }
        'Sampling' {
            switch ($Meta.Section) {
                'Core Sampling' { return 'Response Style' }
                'Penalties'     { return 'Loop Prevention' }
            }
        }
        'Chat' {
            switch ($Meta.Section) {
                'Templates and Reasoning' { return 'Chat Template & Reasoning' }
            }
        }
        'Multimodal' {
            switch ($Meta.Section) {
                'Projector and Vision' { return 'Vision Models' }
            }
        }
        'Router' {
            switch ($Meta.Section) {
                'Router Mode'               { return 'Router Setup' }
                'Server Batching and Cache' { return 'Loading & Reuse' }
            }
        }
    }

    return $Meta.Section
}

function Get-TabColumnLayout {
    param(
        [Parameter(Mandatory = $true)]
        $Page,
        [string]$View
    )

    $clientWidth = [Math]::Max(780, ($Page.ClientSize.Width - 18))
    $settingWidth = if ($View -eq 'Basic') {
        if ($clientWidth -ge 1380) { 248 }
        elseif ($clientWidth -ge 1200) { 232 }
        elseif ($clientWidth -ge 1040) { 214 }
        else { 194 }
    } else {
        if ($clientWidth -ge 1380) { 232 }
        elseif ($clientWidth -ge 1200) { 218 }
        elseif ($clientWidth -ge 1040) { 202 }
        else { 186 }
    }

    $flagWidth = if ($clientWidth -ge 1380) {
        250
    } elseif ($clientWidth -ge 1200) {
        224
    } elseif ($clientWidth -ge 1040) {
        198
    } else {
        174
    }

    $settingX = 38
    $flagX = $settingX + $settingWidth + 14
    $valueX = $flagX + $flagWidth + 16
    $valueWidth = [Math]::Max(180, ($clientWidth - $valueX - 12))

    [PSCustomObject]@{
        Left         = 10
        SettingX     = $settingX
        SettingWidth = $settingWidth
        FlagX        = $flagX
        FlagWidth    = $flagWidth
        ValueX       = $valueX
        ValueWidth   = $valueWidth
        SectionWidth = [Math]::Max(260, ($clientWidth - $settingX - 12))
    }
}

function Get-OptionControlWidth {
    param(
        [Parameter(Mandatory = $true)]
        $State,
        [Parameter(Mandatory = $true)]
        $Columns
    )

    switch ($State.Meta.Type) {
        'number' { return [Math]::Min($Columns.ValueWidth, 150) }
        'decimal' { return [Math]::Min($Columns.ValueWidth, 150) }
        'pair' { return [Math]::Min($Columns.ValueWidth, 150) }
        'flagchoice' { return [Math]::Max(180, [Math]::Min($Columns.ValueWidth, 520)) }
        'combo' {
            $preferred = switch ($State.Meta.Id) {
                'chat_template' { 360 }
                'hf_repo' { 350 }
                'hf_file' { 340 }
                'n_gpu_layers' { 170 }
                'reasoning_format' { 190 }
                'reasoning' { 150 }
                'flash_attn' { 150 }
                default { 320 }
            }
            return [Math]::Max(150, [Math]::Min($Columns.ValueWidth, $preferred))
        }
        'path' { return [Math]::Max(220, [Math]::Min(($Columns.ValueWidth - 84), 760)) }
        'folder' { return [Math]::Max(220, [Math]::Min(($Columns.ValueWidth - 84), 760)) }
        default {
            $preferred = switch ($State.Meta.Id) {
                'api_key' { 420 }
                'hf_repo' { 380 }
                'hf_file' { 340 }
                default { 500 }
            }
            return [Math]::Max(180, [Math]::Min($Columns.ValueWidth, $preferred))
        }
    }
}

function Update-TabColumnLayout {
    param([string]$TabKey)

    $page = $script:TabPages[$TabKey]
    $layout = $script:TabLayouts[$TabKey]
    if (-not $page -or -not $layout) { return }

    $columns = & ${function:Get-TabColumnLayout} -Page $page -View (& ${function:Get-ViewMode})

    if ($layout.UseHeader) {
        $layout.UseHeader.Location = [System.Drawing.Point]::new($columns.Left, 10)
        $layout.SettingHeader.Location = [System.Drawing.Point]::new($columns.SettingX, 10)
        $layout.SettingHeader.Size = [System.Drawing.Size]::new($columns.SettingWidth, 18)
        $layout.FlagHeader.Location = [System.Drawing.Point]::new($columns.FlagX, 10)
        $layout.FlagHeader.Size = [System.Drawing.Size]::new($columns.FlagWidth, 18)
        $layout.ValueHeader.Location = [System.Drawing.Point]::new($columns.ValueX, 10)
        $layout.ValueHeader.Size = [System.Drawing.Size]::new($columns.ValueWidth, 18)
    }

    foreach ($sectionInfo in ($script:SectionLabels | Where-Object { $_.Tab -eq $TabKey })) {
        $sectionInfo.Control.Location = [System.Drawing.Point]::new($columns.SettingX, $sectionInfo.Control.Location.Y)
        $sectionInfo.Control.Size = [System.Drawing.Size]::new($columns.SectionWidth, 18)
    }

    foreach ($state in ($script:OptionStates | Where-Object { $_.Meta.Tab -eq $TabKey })) {
        $state.Override.Location = [System.Drawing.Point]::new($columns.Left, $state.Override.Location.Y)
        $state.Label.Location = [System.Drawing.Point]::new($columns.SettingX, $state.Label.Location.Y)
        $state.Label.Size = [System.Drawing.Size]::new($columns.SettingWidth, 20)
        $state.FlagLabel.Location = [System.Drawing.Point]::new($columns.FlagX, $state.FlagLabel.Location.Y)
        $state.FlagLabel.Size = [System.Drawing.Size]::new($columns.FlagWidth, 18)

        if ($state.Control) {
            $controlWidth = & ${function:Get-OptionControlWidth} -State $state -Columns $columns
            $state.Control.Location = [System.Drawing.Point]::new($columns.ValueX, $state.Control.Location.Y)
            $state.Control.Size = [System.Drawing.Size]::new($controlWidth, $state.Control.Height)

            if ($state.Control -is [System.Windows.Forms.ComboBox]) {
                $state.Control.DropDownWidth = [Math]::Max($controlWidth, [Math]::Min(560, $columns.ValueWidth))
            }

            if ($state.BrowseButton) {
                $state.BrowseButton.Location = [System.Drawing.Point]::new(($columns.ValueX + $controlWidth + 8), $state.BrowseButton.Location.Y)
            }
        }
    }
}

function Update-WindowLayout {
    if (-not $script:form) { return }

    $clientWidth = [Math]::Max(1120, $script:form.ClientSize.Width)
    $clientHeight = [Math]::Max(760, $script:form.ClientSize.Height)

    if ($script:titleLabel) {
        $script:titleLabel.Size = [System.Drawing.Size]::new(($clientWidth - 30), 28)
    }

    if ($script:subtitleLabel) {
        $script:subtitleLabel.Size = [System.Drawing.Size]::new(($clientWidth - 30), 18)
    }

    if ($script:grpRequired) {
        $script:grpRequired.Location = [System.Drawing.Point]::new(10, 62)
        $script:grpRequired.Size = [System.Drawing.Size]::new(($clientWidth - 20), 148)

        $left = 14
        $wideLabelWidth = 128
        $inputX = 150
        $browseWidth = 92
        $buttonGap = 8
        $inputWidth = [Math]::Max(300, ($script:grpRequired.ClientSize.Width - $inputX - $browseWidth - 18))

        if ($script:lblModeRequired) {
            $script:lblModeRequired.Location = [System.Drawing.Point]::new($left, 27)
            $script:lblModeRequired.Size = [System.Drawing.Size]::new(42, 20)
        }
        if ($script:cmbMode) {
            $script:cmbMode.Location = [System.Drawing.Point]::new(60, 24)
            $script:cmbMode.Size = [System.Drawing.Size]::new(196, 25)
        }
        if ($script:lblViewRequired) {
            $script:lblViewRequired.Location = [System.Drawing.Point]::new(276, 27)
            $script:lblViewRequired.Size = [System.Drawing.Size]::new(38, 20)
        }
        if ($script:cmbView) {
            $script:cmbView.Location = [System.Drawing.Point]::new(318, 24)
            $script:cmbView.Size = [System.Drawing.Size]::new(156, 25)
        }
        if ($script:lblServerRequired) {
            $script:lblServerRequired.Location = [System.Drawing.Point]::new($left, 57)
            $script:lblServerRequired.Size = [System.Drawing.Size]::new($wideLabelWidth, 20)
        }
        if ($script:txtServer) {
            $script:txtServer.Location = [System.Drawing.Point]::new($inputX, 54)
            $script:txtServer.Size = [System.Drawing.Size]::new($inputWidth, 25)
        }
        if ($script:btnServer) {
            $script:btnServer.Location = [System.Drawing.Point]::new(($inputX + $inputWidth + $buttonGap), 53)
            $script:btnServer.Size = [System.Drawing.Size]::new($browseWidth, 27)
        }
        if ($script:lblModel) {
            $script:lblModel.Location = [System.Drawing.Point]::new($left, 86)
            $script:lblModel.Size = [System.Drawing.Size]::new($wideLabelWidth, 20)
        }
        if ($script:txtModel) {
            $script:txtModel.Location = [System.Drawing.Point]::new($inputX, 83)
            $script:txtModel.Size = [System.Drawing.Size]::new($inputWidth, 25)
        }
        if ($script:btnModel) {
            $script:btnModel.Location = [System.Drawing.Point]::new(($inputX + $inputWidth + $buttonGap), 82)
            $script:btnModel.Size = [System.Drawing.Size]::new($browseWidth, 27)
        }
        if ($script:lblToolWorkingDir) {
            $script:lblToolWorkingDir.Location = [System.Drawing.Point]::new($left, 115)
            $script:lblToolWorkingDir.Size = [System.Drawing.Size]::new($wideLabelWidth, 20)
        }
        if ($script:txtToolWorkingDir) {
            $script:txtToolWorkingDir.Location = [System.Drawing.Point]::new($inputX, 112)
            $script:txtToolWorkingDir.Size = [System.Drawing.Size]::new($inputWidth, 25)
        }
        if ($script:btnToolWorkingDir) {
            $script:btnToolWorkingDir.Location = [System.Drawing.Point]::new(($inputX + $inputWidth + $buttonGap), 111)
            $script:btnToolWorkingDir.Size = [System.Drawing.Size]::new($browseWidth, 27)
        }
    }

    if ($script:lblModeHint) {
        $script:lblModeHint.Location = [System.Drawing.Point]::new(16, ($script:grpRequired.Bottom + 7))
        $script:lblModeHint.Size = [System.Drawing.Size]::new(($clientWidth - 30), 18)
    }

    if ($script:mainSplit) {
        $splitTop = if ($script:lblModeHint) { $script:lblModeHint.Bottom + 9 } else { 196 }
        $script:mainSplit.Location = [System.Drawing.Point]::new(10, $splitTop)
        $script:mainSplit.Size = [System.Drawing.Size]::new(($clientWidth - 20), [Math]::Max(320, ($clientHeight - $splitTop - 10)))

        $maxSplitter = [Math]::Max($script:mainSplit.Panel1MinSize, ($script:mainSplit.Height - $script:mainSplit.Panel2MinSize - $script:mainSplit.SplitterWidth))
        if ($script:mainSplit.SplitterDistance -gt $maxSplitter) {
            $script:mainSplit.SplitterDistance = $maxSplitter
        }
        if ($script:mainSplit.SplitterDistance -lt $script:mainSplit.Panel1MinSize) {
            $script:mainSplit.SplitterDistance = $script:mainSplit.Panel1MinSize
        }
    }

    if ($script:mainSplit -and $script:previewLabel) {
        $script:previewLabel.Location = [System.Drawing.Point]::new(10, 10)
    }

    if ($script:mainSplit -and $script:txtPreview) {
        $previewWidth = [Math]::Max(320, ($script:mainSplit.Panel2.ClientSize.Width - 20))
        $previewHeight = [Math]::Max(110, ($script:mainSplit.Panel2.ClientSize.Height - 80))
        $script:txtPreview.Location = [System.Drawing.Point]::new(10, 32)
        $script:txtPreview.Size = [System.Drawing.Size]::new($previewWidth, $previewHeight)
    }

    if ($script:mainSplit -and $script:btnCopy) {
        $buttonsY = [Math]::Max(0, ($script:mainSplit.Panel2.ClientSize.Height - 40))
        $script:btnCopy.Location = [System.Drawing.Point]::new(10, $buttonsY)
        $script:btnReset.Location = [System.Drawing.Point]::new(143, $buttonsY)
        $script:btnLaunch.Location = [System.Drawing.Point]::new([Math]::Max(320, ($script:mainSplit.Panel2.ClientSize.Width - 250)), ($buttonsY - 4))
    }

    foreach ($tabKey in $script:TabOrder) {
        & ${function:Update-TabColumnLayout} -TabKey $tabKey
    }
}

function Set-OptionRowVisible {
    param(
        [Parameter(Mandatory = $true)]
        $State,
        [bool]$Visible
    )

    $State.Override.Visible = $Visible
    $State.Label.Visible = $Visible
    if ($State.FlagLabel) { $State.FlagLabel.Visible = $Visible }
    if ($State.Control) { $State.Control.Visible = $Visible }
    if ($State.BrowseButton) { $State.BrowseButton.Visible = $Visible }
}

function Set-OptionRowPosition {
    param(
        [Parameter(Mandatory = $true)]
        $State,
        [int]$Y
    )

    $State.Override.Location = [System.Drawing.Point]::new($State.Override.Location.X, ($Y + 2))
    $State.Label.Location = [System.Drawing.Point]::new($State.Label.Location.X, ($Y + 3))
    if ($State.FlagLabel) {
        $State.FlagLabel.Location = [System.Drawing.Point]::new($State.FlagLabel.Location.X, ($Y + 4))
    }

    if ($State.Control) {
        $State.Control.Location = [System.Drawing.Point]::new($State.Control.Location.X, $Y)
    }

    if ($State.BrowseButton) {
        $State.BrowseButton.Location = [System.Drawing.Point]::new($State.BrowseButton.Location.X, $Y)
    }
}

function Update-ViewMode {
    $view = & ${function:Get-ViewMode}
    $isBasic = $view -eq 'Basic'
    $selectedTabKey = if ($script:MainTabs -and $script:MainTabs.SelectedTab) { [string]$script:MainTabs.SelectedTab.Tag } else { '' }
    $visibleTabs = New-Object System.Collections.Generic.List[string]

    foreach ($sectionInfo in $script:SectionLabels) {
        $sectionInfo.Control.Visible = $false
    }

    foreach ($tabKey in $script:TabOrder) {
        $page = $script:TabPages[$tabKey]
        if (-not $page) { continue }
        $page.Text = & ${function:Get-ViewTabTitle} -TabKey $tabKey -View $view

        $y = 34
        $lastSection = ''
        $hasVisibleRows = $false

        foreach ($state in ($script:OptionStates | Where-Object { $_.Meta.Tab -eq $tabKey })) {
            $rowVisible = (-not $isBasic) -or $state.Meta.Basic
            & ${function:Set-OptionRowVisible} -State $state -Visible $rowVisible
            if (-not $rowVisible) { continue }

            $sectionTitle = & ${function:Get-ViewSectionTitle} -Meta $state.Meta -View $view

            if ($lastSection -ne $sectionTitle) {
                if ($y -gt 34) {
                    $y += 12
                }

                $sectionInfo = $script:SectionLabels | Where-Object { $_.Tab -eq $tabKey -and $_.Section -eq $state.Meta.Section } | Select-Object -First 1
                if ($sectionInfo) {
                    $sectionInfo.Control.Text = $sectionTitle
                    $sectionInfo.Control.Location = [System.Drawing.Point]::new(38, $y)
                    $sectionInfo.Control.Visible = $true
                }

                $y += 20
                $lastSection = $sectionTitle
            }

            & ${function:Set-OptionRowPosition} -State $state -Y $y
            $y += 32
            $hasVisibleRows = $true
        }

        $page.AutoScrollMinSize = [System.Drawing.Size]::new(0, [Math]::Max(0, ($y + 12)))

        $includeTab = $hasVisibleRows
        if ($tabKey -eq 'AllOptions' -or $tabKey -eq 'Advanced') {
            $includeTab = -not $isBasic
        }

        if ($includeTab) {
            [void]$visibleTabs.Add($tabKey)
        }
    }

    if ($script:MainTabs) {
        $script:MainTabs.SuspendLayout()
        $script:MainTabs.TabPages.Clear()
        foreach ($tabKey in $visibleTabs) {
            $page = $script:TabPages[$tabKey]
            if ($page) {
                [void]$script:MainTabs.TabPages.Add($page)
            }
        }

        $targetPage = $null
        if ($selectedTabKey) {
            $candidatePage = $script:TabPages[$selectedTabKey]
            if ($candidatePage -and ($script:MainTabs.TabPages.IndexOf($candidatePage) -ge 0)) {
                $targetPage = $candidatePage
            }
        }
        if (-not $targetPage -and $script:MainTabs.TabPages.Count -gt 0) {
            $targetPage = $script:MainTabs.TabPages[0]
        }
        if ($targetPage) {
            $script:MainTabs.SelectedTab = $targetPage
        }

        $script:MainTabs.ResumeLayout()
    }

    & ${function:Update-WindowLayout}
    & ${function:Refresh-Preview}
}

function Get-OptionStateById {
    param([string]$Id)
    return $script:OptionStatesById[$Id]
}

function Test-OverrideHasValue {
    param([string]$Id)

    $state = Get-OptionStateById -Id $Id
    if (-not $state) { return $false }
    if (-not $state.Override.Checked) { return $false }

    switch ($state.Meta.Type) {
        'flag' { return $true }
        'pair' { return $true }
        'number' { return $true }
        'decimal' { return $true }
        'flagchoice' { return -not [string]::IsNullOrWhiteSpace([string]$state.Control.SelectedItem) }
        default { return -not [string]::IsNullOrWhiteSpace($state.Control.Text) }
    }
}

function Test-MainModelSourcePresent {
    if (-not [string]::IsNullOrWhiteSpace($script:txtModel.Text)) {
        return $true
    }

    return (
        (Test-OverrideHasValue 'model_url') -or
        (Test-OverrideHasValue 'docker_repo') -or
        (Test-OverrideHasValue 'hf_repo') -or
        (Test-OverrideHasValue 'default_profile')
    )
}

function Test-RouterSourcePresent {
    return (
        (Test-OverrideHasValue 'models_dir') -or
        (Test-OverrideHasValue 'models_preset')
    )
}

function Jump-ToOption {
    param(
        [Parameter(Mandatory = $true)]
        $State
    )

    $page = $script:TabPages[$State.Meta.Tab]
    if (-not $page) { return }

    $script:MainTabs.SelectedTab = $page
    $target = if ($State.Control) { $State.Control } else { $State.Override }
    if ($target) {
        $page.ScrollControlIntoView($target)
        [void]$target.Focus()
    }
}

function Add-OptionRow {
    param(
        [Parameter(Mandatory = $true)]
        $Option
    )

    $page = $script:TabPages[$Option.Tab]
    $layout = $script:TabLayouts[$Option.Tab]
    $controlLeft = 405

    if (-not $layout.HeaderAdded) {
        $useHeader = New-Object System.Windows.Forms.Label
        $useHeader.Text = 'Use'
        $useHeader.Location = [System.Drawing.Point]::new(10, 10)
        $useHeader.Size = [System.Drawing.Size]::new(30, 18)
        $useHeader.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
        $useHeader.ForeColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
        $page.Controls.Add($useHeader)

        $settingHeader = New-Object System.Windows.Forms.Label
        $settingHeader.Text = 'Setting'
        $settingHeader.Location = [System.Drawing.Point]::new(38, 10)
        $settingHeader.Size = [System.Drawing.Size]::new(165, 18)
        $settingHeader.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
        $settingHeader.ForeColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
        $page.Controls.Add($settingHeader)

        $flagHeader = New-Object System.Windows.Forms.Label
        $flagHeader.Text = 'CLI Flag'
        $flagHeader.Location = [System.Drawing.Point]::new(220, 10)
        $flagHeader.Size = [System.Drawing.Size]::new(170, 18)
        $flagHeader.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
        $flagHeader.ForeColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
        $page.Controls.Add($flagHeader)

        $valueHeader = New-Object System.Windows.Forms.Label
        $valueHeader.Text = 'Value'
        $valueHeader.Location = [System.Drawing.Point]::new($controlLeft, 10)
        $valueHeader.Size = [System.Drawing.Size]::new(200, 18)
        $valueHeader.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
        $valueHeader.ForeColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
        $page.Controls.Add($valueHeader)

        $layout.UseHeader = $useHeader
        $layout.SettingHeader = $settingHeader
        $layout.FlagHeader = $flagHeader
        $layout.ValueHeader = $valueHeader
        $layout.Y = 34
        $layout.HeaderAdded = $true
    }

    if ($layout.LastSection -ne $Option.Section) {
        if ($layout.Y -gt 34) {
            $layout.Y += 12
        }

        $sectionLabel = New-Object System.Windows.Forms.Label
        $sectionLabel.Text = $Option.Section
        $sectionLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
        $sectionLabel.ForeColor = [System.Drawing.Color]::FromArgb(95, 95, 95)
        $sectionLabel.Location = [System.Drawing.Point]::new(38, $layout.Y)
        $sectionLabel.Size = [System.Drawing.Size]::new(900, 18)
        $sectionLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
        $page.Controls.Add($sectionLabel)
        [void]$script:SectionLabels.Add([PSCustomObject]@{
            Tab     = $Option.Tab
            Section = $Option.Section
            Control = $sectionLabel
        })

        $layout.Y += 20
        $layout.LastSection = $Option.Section
    }

    $rowHeight = 32
    $checkbox = New-Object System.Windows.Forms.CheckBox
    $checkbox.Location = [System.Drawing.Point]::new(10, ($layout.Y + 2))
    $checkbox.Size = [System.Drawing.Size]::new(16, 20)
    $checkbox.Checked = $false
    $checkbox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $page.Controls.Add($checkbox)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Option.Label
    $label.Location = [System.Drawing.Point]::new(38, ($layout.Y + 3))
    $label.Size = [System.Drawing.Size]::new(170, 20)
    $label.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $label.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 160)
    $label.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $label.AutoEllipsis = $true
    $page.Controls.Add($label)

    $flagLabel = New-Object System.Windows.Forms.Label
    $flagLabel.Text = $Option.DisplayFlag
    $flagLabel.Location = [System.Drawing.Point]::new(220, ($layout.Y + 4))
    $flagLabel.Size = [System.Drawing.Size]::new(170, 18)
    $flagLabel.Font = New-Object System.Drawing.Font('Consolas', 8.25)
    $flagLabel.ForeColor = [System.Drawing.Color]::FromArgb(145, 145, 145)
    $flagLabel.AutoEllipsis = $true
    $flagLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $page.Controls.Add($flagLabel)

    $control = $null
    $browseButton = $null

    switch ($Option.Type) {
        'number' {
            $control = New-Object System.Windows.Forms.NumericUpDown
            $control.Location = [System.Drawing.Point]::new($controlLeft, $layout.Y)
            $control.Size = [System.Drawing.Size]::new(140, 24)
            $control.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $control.DecimalPlaces = 0
            $control.Minimum = [decimal]$Option.Min
            $control.Maximum = [decimal]$Option.Max
            $control.Value = [decimal]$Option.Default
            $control.Enabled = $false
            $control.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            if ($Option.Increment -ne $null) {
                $control.Increment = [decimal]$Option.Increment
            }
            $page.Controls.Add($control)
        }
        'decimal' {
            $control = New-Object System.Windows.Forms.NumericUpDown
            $control.Location = [System.Drawing.Point]::new($controlLeft, $layout.Y)
            $control.Size = [System.Drawing.Size]::new(140, 24)
            $control.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $control.DecimalPlaces = $Option.Decimals
            $control.Minimum = [decimal]$Option.Min
            $control.Maximum = [decimal]$Option.Max
            $control.Value = [decimal]$Option.Default
            $control.Enabled = $false
            $control.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            if ($Option.Increment -ne $null) {
                $control.Increment = [decimal]$Option.Increment
            }
            $page.Controls.Add($control)
        }
        'combo' {
            $control = New-Object System.Windows.Forms.ComboBox
            $control.Location = [System.Drawing.Point]::new($controlLeft, $layout.Y)
            $control.Size = [System.Drawing.Size]::new(300, 24)
            $control.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $control.DropDownStyle = if ($Option.Editable) { [System.Windows.Forms.ComboBoxStyle]::DropDown } else { [System.Windows.Forms.ComboBoxStyle]::DropDownList }
            $control.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            foreach ($choice in $Option.Choices) {
                [void]$control.Items.Add($choice)
            }
            if ($Option.Default -ne $null) {
                $control.Text = [string]$Option.Default
                if (-not $Option.Editable) {
                    $control.SelectedItem = [string]$Option.Default
                }
            }
            $control.Enabled = $false
            $page.Controls.Add($control)
        }
        'pair' {
            $control = New-Object System.Windows.Forms.ComboBox
            $control.Location = [System.Drawing.Point]::new($controlLeft, $layout.Y)
            $control.Size = [System.Drawing.Size]::new(170, 24)
            $control.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $control.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
            $control.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            [void]$control.Items.Add('Enabled')
            [void]$control.Items.Add('Disabled')
            $control.SelectedItem = if ($Option.Default) { [string]$Option.Default } else { 'Enabled' }
            $control.Enabled = $false
            $page.Controls.Add($control)
        }
        'flagchoice' {
            $control = New-Object System.Windows.Forms.ComboBox
            $control.Location = [System.Drawing.Point]::new($controlLeft, $layout.Y)
            $control.Size = [System.Drawing.Size]::new(430, 24)
            $control.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $control.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
            $control.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            foreach ($choice in $Option.Choices) {
                [void]$control.Items.Add($choice.Label)
            }
            if ($Option.Default) {
                $control.SelectedItem = [string]$Option.Default
            } elseif ($control.Items.Count -gt 0) {
                $control.SelectedIndex = 0
            }
            $control.Enabled = $false
            $page.Controls.Add($control)
        }
        'path' {
            $control = New-Object System.Windows.Forms.TextBox
            $control.Location = [System.Drawing.Point]::new($controlLeft, $layout.Y)
            $control.Size = [System.Drawing.Size]::new(420, 24)
            $control.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $control.Text = [string]$Option.Default
            $control.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
            $control.Enabled = $false
            $control.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            $page.Controls.Add($control)

            $localControl = $control
            $localOption = $Option
            $browseButton = New-Object System.Windows.Forms.Button
            $browseButton.Text = 'Browse'
            $browseButton.Location = [System.Drawing.Point]::new(836, $layout.Y)
            $browseButton.Size = [System.Drawing.Size]::new(76, 24)
            $browseButton.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
            $browseButton.Enabled = $false
            $browseButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            $browseButton.Add_Click({
                $startDir = if ($localControl.Text -and (Test-Path $localControl.Text)) { Split-Path -Parent $localControl.Text } else { $script:BatDir }
                $selected = & ${function:Browse-Path} -Title ('Select ' + $localOption.Label) -Mode $localOption.BrowseMode -Filter $localOption.Filter -StartDir $startDir
                if ($selected) {
                    $localControl.Text = $selected
                }
            }.GetNewClosure())
            $page.Controls.Add($browseButton)
        }
        'folder' {
            $control = New-Object System.Windows.Forms.TextBox
            $control.Location = [System.Drawing.Point]::new($controlLeft, $layout.Y)
            $control.Size = [System.Drawing.Size]::new(420, 24)
            $control.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $control.Text = [string]$Option.Default
            $control.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
            $control.Enabled = $false
            $control.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            $page.Controls.Add($control)

            $localControl = $control
            $localOption = $Option
            $browseButton = New-Object System.Windows.Forms.Button
            $browseButton.Text = 'Browse'
            $browseButton.Location = [System.Drawing.Point]::new(836, $layout.Y)
            $browseButton.Size = [System.Drawing.Size]::new(76, 24)
            $browseButton.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
            $browseButton.Enabled = $false
            $browseButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            $browseButton.Add_Click({
                $startDir = if ($localControl.Text -and (Test-Path $localControl.Text)) { $localControl.Text } else { $script:BatDir }
                $selected = & ${function:Browse-Path} -Title ('Select ' + $localOption.Label) -Mode 'folder' -Filter $localOption.Filter -StartDir $startDir
                if ($selected) {
                    $localControl.Text = $selected
                }
            }.GetNewClosure())
            $page.Controls.Add($browseButton)
        }
        default {
            $control = New-Object System.Windows.Forms.TextBox
            $control.Location = [System.Drawing.Point]::new($controlLeft, $layout.Y)
            $control.Size = [System.Drawing.Size]::new(500, 24)
            $control.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $control.Text = [string]$Option.Default
            $control.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
            $control.Enabled = $false
            $control.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            $page.Controls.Add($control)
        }
    }

    if ($Option.Tooltip) {
        $tooltip = New-Object System.Windows.Forms.ToolTip
        $tooltip.AutoPopDelay = 20000
        $tooltip.InitialDelay = 250
        $tooltip.SetToolTip($label, $Option.Tooltip)
        $tooltip.SetToolTip($flagLabel, $Option.DisplayFlag)
        $tooltip.SetToolTip($checkbox, $Option.Tooltip)
        if ($control) { $tooltip.SetToolTip($control, $Option.Tooltip) }
        if ($browseButton) { $tooltip.SetToolTip($browseButton, $Option.Tooltip) }
    }

    $state = [PSCustomObject]@{
        Meta         = $Option
        Override     = $checkbox
        Label        = $label
        FlagLabel    = $flagLabel
        Control      = $control
        BrowseButton = $browseButton
        Page         = $page
        Y            = $layout.Y
    }

    $script:OptionStatesById[$Option.Id] = $state
    [void]$script:OptionStates.Add($state)

    $localState = $state
    $checkbox.Add_CheckedChanged({
        $enabled = $localState.Override.Checked
        $localState.Label.ForeColor = if ($enabled) { [System.Drawing.Color]::FromArgb(35, 35, 35) } else { [System.Drawing.Color]::FromArgb(160, 160, 160) }
        $localState.FlagLabel.ForeColor = if ($enabled) { [System.Drawing.Color]::FromArgb(75, 75, 75) } else { [System.Drawing.Color]::FromArgb(145, 145, 145) }
        if ($localState.Control) { $localState.Control.Enabled = $enabled }
        if ($localState.BrowseButton) { $localState.BrowseButton.Enabled = $enabled }
        & ${function:Refresh-Preview}
    }.GetNewClosure())

    if ($control) {
        switch ($Option.Type) {
            'number'      { $control.Add_ValueChanged({ & ${function:Refresh-Preview} }.GetNewClosure()) }
            'decimal'     { $control.Add_ValueChanged({ & ${function:Refresh-Preview} }.GetNewClosure()) }
            'combo'       { $control.Add_TextChanged({ & ${function:Refresh-Preview} }.GetNewClosure()); $control.Add_SelectedIndexChanged({ & ${function:Refresh-Preview} }.GetNewClosure()) }
            'pair'        { $control.Add_SelectedIndexChanged({ & ${function:Refresh-Preview} }.GetNewClosure()) }
            'flagchoice'  { $control.Add_SelectedIndexChanged({ & ${function:Refresh-Preview} }.GetNewClosure()) }
            default       { $control.Add_TextChanged({ & ${function:Refresh-Preview} }.GetNewClosure()) }
        }
    }

    $layout.Y += $rowHeight
}

$tabSpecs = @(
    @{ Key = 'Server';      Title = 'Server' },
    @{ Key = 'Model';       Title = 'Model Sources' },
    @{ Key = 'Performance'; Title = 'Performance' },
    @{ Key = 'Sampling';    Title = 'Sampling' },
    @{ Key = 'Chat';        Title = 'Chat' },
    @{ Key = 'Multimodal';  Title = 'Multimodal' },
    @{ Key = 'Speculative'; Title = 'Speculative' },
    @{ Key = 'Router';      Title = 'Router' },
    @{ Key = 'Logging';     Title = 'Logging' },
    @{ Key = 'Advanced';    Title = 'Advanced' },
    @{ Key = 'AllOptions';  Title = 'All Options' }
)

$chatTemplates = @(
    'bailing', 'bailing-think', 'bailing2', 'chatglm3', 'chatglm4', 'chatml', 'command-r',
    'deepseek', 'deepseek-ocr', 'deepseek2', 'deepseek3', 'exaone-moe', 'exaone3', 'exaone4',
    'falcon3', 'gemma', 'gigachat', 'glmedge', 'gpt-oss', 'granite', 'grok-2', 'hunyuan-dense',
    'hunyuan-moe', 'kimi-k2', 'llama2', 'llama2-sys', 'llama2-sys-bos', 'llama2-sys-strip',
    'llama3', 'llama4', 'megrez', 'minicpm', 'mistral-v1', 'mistral-v3', 'mistral-v3-tekken',
    'mistral-v7', 'mistral-v7-tekken', 'monarch', 'openchat', 'orion', 'pangu-embedded', 'phi3',
    'phi4', 'rwkv-world', 'seed_oss', 'smolvlm', 'solar-open', 'vicuna', 'vicuna-orca', 'yandex',
    'zephyr'
)

$cacheTypes = @('f32', 'f16', 'bf16', 'q8_0', 'q4_0', 'q4_1', 'iq4_nl', 'q5_0', 'q5_1')

Add-OptionMeta (New-OptionMeta -Id 'host' -Tab 'Server' -Section 'Network' -Label 'Host / Bind Address' -Type 'text' -Flag '--host' -Default '127.0.0.1' -Basic $true -Tooltip "This is the network address llama-server listens on.`n`nRecommendation: leave this unchecked for a normal personal setup. 127.0.0.1 keeps the server local to your own PC, which is the safest beginner choice.`n`nChange it only if another device on your LAN needs to connect.")
Add-OptionMeta (New-OptionMeta -Id 'port' -Tab 'Server' -Section 'Network' -Label 'Port' -Type 'number' -Flag '--port' -Default 8080 -Min 1 -Max 65535 -Basic $true -Tooltip "This is the port number clients use to reach the server.`n`nRecommendation: leave this unchecked unless 8080 is already busy or you want a different port for a specific app.")
Add-OptionMeta (New-OptionMeta -Id 'reuse_port' -Tab 'Server' -Section 'Network' -Label 'Reuse Port' -Type 'flag' -Flag '--reuse-port' -Tooltip 'Allow multiple sockets to bind the same port.')
Add-OptionMeta (New-OptionMeta -Id 'timeout' -Tab 'Server' -Section 'Network' -Label 'Read/Write Timeout (s)' -Type 'number' -Flag '--timeout' -Default 600 -Min 1 -Max 86400 -Tooltip 'HTTP read and write timeout in seconds.')
Add-OptionMeta (New-OptionMeta -Id 'threads_http' -Tab 'Server' -Section 'Network' -Label 'HTTP Threads' -Type 'number' -Flag '--threads-http' -Default -1 -Min -1 -Max 256 -Tooltip 'Threads used to process HTTP requests. -1 uses server default.')
Add-OptionMeta (New-OptionMeta -Id 'api_prefix' -Tab 'Server' -Section 'Network' -Label 'API Prefix' -Type 'text' -Flag '--api-prefix' -Tooltip 'Serve the API under a custom prefix.')
Add-OptionMeta (New-OptionMeta -Id 'static_path' -Tab 'Server' -Section 'Web UI and Static Files' -Label 'Static Files Path' -Type 'folder' -Flag '--path' -BrowseMode 'folder' -Tooltip 'Directory to serve static files from.')
Add-OptionMeta (New-OptionMeta -Id 'webui' -Tab 'Server' -Section 'Web UI and Static Files' -Label 'Web UI' -Type 'pair' -Flag '--webui' -NegFlag '--no-webui' -Default 'Enabled' -Tooltip 'Force Web UI on or off.')
Add-OptionMeta (New-OptionMeta -Id 'webui_config' -Tab 'Server' -Section 'Web UI and Static Files' -Label 'Web UI Config JSON' -Type 'text' -Flag '--webui-config' -Tooltip 'Inline JSON for Web UI defaults.')
Add-OptionMeta (New-OptionMeta -Id 'webui_config_file' -Tab 'Server' -Section 'Web UI and Static Files' -Label 'Web UI Config File' -Type 'path' -Flag '--webui-config-file' -BrowseMode 'file' -Filter 'JSON files (*.json)|*.json|All files (*.*)|*.*' -Tooltip 'JSON file for Web UI defaults.')
Add-OptionMeta (New-OptionMeta -Id 'webui_mcp_proxy' -Tab 'Server' -Section 'Web UI and Static Files' -Label 'Web UI MCP Proxy' -Type 'pair' -Flag '--webui-mcp-proxy' -NegFlag '--no-webui-mcp-proxy' -Default 'Enabled' -Tooltip 'Enable or disable the experimental MCP CORS proxy.')
Add-OptionMeta (New-OptionMeta -Id 'tools' -Tab 'Server' -Section 'Web UI and Static Files' -Label 'Built-in Tools' -Type 'text' -Flag '--tools' -Tooltip 'Comma-separated built-in tools, or all.')
Add-OptionMeta (New-OptionMeta -Id 'api_key' -Tab 'Server' -Section 'Authentication and TLS' -Label 'API Key(s)' -Type 'text' -Flag '--api-key' -Basic $true -Tooltip "Adds a password-like key for API clients.`n`nRecommendation: leave this unchecked if the server stays on localhost and only you use it. Turn it on when other apps, browser tools, or other machines will connect.`n`nYou can enter multiple keys as a comma-separated list.")
Add-OptionMeta (New-OptionMeta -Id 'api_key_file' -Tab 'Server' -Section 'Authentication and TLS' -Label 'API Key File' -Type 'path' -Flag '--api-key-file' -BrowseMode 'file' -Filter 'Text files (*.txt)|*.txt|All files (*.*)|*.*' -Tooltip 'File containing API keys.')
Add-OptionMeta (New-OptionMeta -Id 'ssl_key_file' -Tab 'Server' -Section 'Authentication and TLS' -Label 'SSL Key File' -Type 'path' -Flag '--ssl-key-file' -BrowseMode 'file' -Filter 'PEM files (*.pem)|*.pem|All files (*.*)|*.*' -Tooltip 'PEM-encoded SSL private key.')
Add-OptionMeta (New-OptionMeta -Id 'ssl_cert_file' -Tab 'Server' -Section 'Authentication and TLS' -Label 'SSL Certificate File' -Type 'path' -Flag '--ssl-cert-file' -BrowseMode 'file' -Filter 'PEM/CRT files (*.pem;*.crt)|*.pem;*.crt|All files (*.*)|*.*' -Tooltip 'PEM-encoded SSL certificate.')
Add-OptionMeta (New-OptionMeta -Id 'metrics' -Tab 'Server' -Section 'Monitoring and Endpoints' -Label 'Metrics Endpoint' -Type 'flag' -Flag '--metrics' -Tooltip 'Enable Prometheus metrics endpoint.')
Add-OptionMeta (New-OptionMeta -Id 'props' -Tab 'Server' -Section 'Monitoring and Endpoints' -Label 'Props Endpoint' -Type 'flag' -Flag '--props' -Tooltip 'Enable POST /props for global property changes.')
Add-OptionMeta (New-OptionMeta -Id 'slots' -Tab 'Server' -Section 'Monitoring and Endpoints' -Label 'Slots Endpoint' -Type 'pair' -Flag '--slots' -NegFlag '--no-slots' -Default 'Enabled' -Tooltip 'Expose or hide slots monitoring endpoint.')
Add-OptionMeta (New-OptionMeta -Id 'slot_save_path' -Tab 'Server' -Section 'Monitoring and Endpoints' -Label 'Slot Save Path' -Type 'folder' -Flag '--slot-save-path' -BrowseMode 'folder' -Tooltip 'Directory used to save slot KV cache.')
Add-OptionMeta (New-OptionMeta -Id 'media_path' -Tab 'Server' -Section 'Monitoring and Endpoints' -Label 'Media Path' -Type 'folder' -Flag '--media-path' -BrowseMode 'folder' -Tooltip 'Directory for local media files that can be referenced by file:// URLs.')

Add-OptionMeta (New-OptionMeta -Id 'model_url' -Tab 'Model' -Section 'Alternative Model Sources' -Label 'Model URL' -Type 'text' -Flag '--model-url' -Tooltip 'Download and use a model directly from a URL.')
Add-OptionMeta (New-OptionMeta -Id 'docker_repo' -Tab 'Model' -Section 'Alternative Model Sources' -Label 'Docker Repo' -Type 'text' -Flag '--docker-repo' -Tooltip 'Docker Hub model repository, for example gemma3.')
Add-OptionMeta (New-OptionMeta -Id 'hf_repo' -Tab 'Model' -Section 'Alternative Model Sources' -Label 'Hugging Face Repo' -Type 'text' -Flag '--hf-repo' -Basic $true -Tooltip "Downloads a model directly from Hugging Face instead of using a local GGUF path.`n`nRecommendation: this is the easiest remote-model workflow for most people in 2026. Enter it as 'user/model[:quant]'. llama.cpp will usually try a common GGUF quant automatically, and it can also auto-download an mmproj file when the repo provides one.")
Add-OptionMeta (New-OptionMeta -Id 'hf_file' -Tab 'Model' -Section 'Alternative Model Sources' -Label 'Hugging Face File' -Type 'text' -Flag '--hf-file' -Basic $true -Tooltip "Picks the exact file inside the Hugging Face repo.`n`nRecommendation: use this when the repo has several GGUF files and you want a specific quant such as Q4_K_M or Q8_0, or when the repo's default guess is not the one you want.")
Add-OptionMeta (New-OptionMeta -Id 'hf_token' -Tab 'Model' -Section 'Alternative Model Sources' -Label 'Hugging Face Token' -Type 'text' -Flag '--hf-token' -Tooltip 'Access token for private Hugging Face repos.')
Add-OptionMeta (New-OptionMeta -Id 'offline' -Tab 'Model' -Section 'Alternative Model Sources' -Label 'Offline Mode' -Type 'flag' -Flag '--offline' -Tooltip 'Force cache-only model loading and disable network access.')
Add-OptionMeta (New-OptionMeta -Id 'alias' -Tab 'Model' -Section 'Metadata' -Label 'Alias' -Type 'text' -Flag '--alias' -Tooltip 'Comma-separated model aliases exposed by the API.')
Add-OptionMeta (New-OptionMeta -Id 'tags' -Tab 'Model' -Section 'Metadata' -Label 'Tags' -Type 'text' -Flag '--tags' -Tooltip 'Comma-separated informational model tags.')
Add-OptionMeta (New-OptionMeta -Id 'default_profile' -Tab 'Model' -Section 'Built-in Default Profiles' -Label 'Default Downloaded Profile' -Type 'flagchoice' -Choices @(
    (New-Choice 'EmbeddingGemma default' '--embd-gemma-default'),
    (New-Choice 'Qwen 2.5 Coder 1.5B FIM default' '--fim-qwen-1.5b-default'),
    (New-Choice 'Qwen 2.5 Coder 3B FIM default' '--fim-qwen-3b-default'),
    (New-Choice 'Qwen 2.5 Coder 7B FIM default' '--fim-qwen-7b-default'),
    (New-Choice 'Qwen 2.5 Coder 7B speculative' '--fim-qwen-7b-spec'),
    (New-Choice 'Qwen 2.5 Coder 14B speculative' '--fim-qwen-14b-spec'),
    (New-Choice 'Qwen 3 Coder 30B default' '--fim-qwen-30b-default'),
    (New-Choice 'gpt-oss-20b default' '--gpt-oss-20b-default'),
    (New-Choice 'gpt-oss-120b default' '--gpt-oss-120b-default'),
    (New-Choice 'Gemma 3 Vision 4B default' '--vision-gemma-4b-default'),
    (New-Choice 'Gemma 3 Vision 12B default' '--vision-gemma-12b-default')
) -Tooltip 'Preset model shortcuts documented by llama-server.' -DisplayFlag '--embd-gemma-default / --fim-qwen-* / --gpt-oss-* / --vision-gemma-*')
Add-OptionMeta (New-OptionMeta -Id 'utility_action' -Tab 'Model' -Section 'Utilities' -Label 'Utility Command' -Type 'flagchoice' -Choices @(
    (New-Choice 'Show help and exit' '--help'),
    (New-Choice 'Show version and exit' '--version'),
    (New-Choice 'Show license and exit' '--license'),
    (New-Choice 'Show cache list and exit' '--cache-list'),
    (New-Choice 'Print bash completion and exit' '--completion-bash'),
    (New-Choice 'List devices and exit' '--list-devices')
) -Tooltip 'One-shot utility actions. These usually run alone and then exit.' -DisplayFlag '--help / --version / --license / --cache-list / --completion-bash / --list-devices')

Add-OptionMeta (New-OptionMeta -Id 'threads' -Tab 'Performance' -Section 'CPU and Threading' -Label 'CPU Threads' -Type 'number' -Flag '--threads' -Default -1 -Min -1 -Max 256 -Basic $true -Tooltip "Controls how many CPU worker threads generation can use.`n`nRecommendation: leave this unchecked first. The automatic choice is usually good. Override it only if you want to cap CPU usage, reduce heat or noise, or you already know a better number for your machine.")
Add-OptionMeta (New-OptionMeta -Id 'threads_batch' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Batch Threads' -Type 'number' -Flag '--threads-batch' -Default -1 -Min -1 -Max 256 -Tooltip 'Prompt and batch processing threads.')
Add-OptionMeta (New-OptionMeta -Id 'cpu_mask' -Tab 'Performance' -Section 'CPU and Threading' -Label 'CPU Mask' -Type 'text' -Flag '--cpu-mask' -Tooltip 'CPU affinity mask in hex.')
Add-OptionMeta (New-OptionMeta -Id 'cpu_range' -Tab 'Performance' -Section 'CPU and Threading' -Label 'CPU Range' -Type 'text' -Flag '--cpu-range' -Tooltip 'CPU range like 0-7.')
Add-OptionMeta (New-OptionMeta -Id 'cpu_strict' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Strict CPU Placement' -Type 'combo' -Flag '--cpu-strict' -Choices @('0', '1') -Default '0' -Tooltip 'Set strict CPU placement.')
Add-OptionMeta (New-OptionMeta -Id 'prio' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Priority' -Type 'combo' -Flag '--prio' -Choices @('-1', '0', '1', '2', '3') -Default '0' -Tooltip 'low(-1), normal(0), medium(1), high(2), realtime(3).')
Add-OptionMeta (New-OptionMeta -Id 'poll' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Polling Level' -Type 'number' -Flag '--poll' -Default 50 -Min 0 -Max 100 -Tooltip 'Polling level while waiting for work.')
Add-OptionMeta (New-OptionMeta -Id 'cpu_mask_batch' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Batch CPU Mask' -Type 'text' -Flag '--cpu-mask-batch' -Tooltip 'Batch CPU affinity mask in hex.')
Add-OptionMeta (New-OptionMeta -Id 'cpu_range_batch' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Batch CPU Range' -Type 'text' -Flag '--cpu-range-batch' -Tooltip 'Batch CPU range like 0-7.')
Add-OptionMeta (New-OptionMeta -Id 'cpu_strict_batch' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Strict Batch Placement' -Type 'combo' -Flag '--cpu-strict-batch' -Choices @('0', '1') -Default '0' -Tooltip 'Set strict CPU placement for batch work.')
Add-OptionMeta (New-OptionMeta -Id 'prio_batch' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Batch Priority' -Type 'combo' -Flag '--prio-batch' -Choices @('0', '1', '2', '3') -Default '0' -Tooltip 'Batch priority: normal(0) to realtime(3).')
Add-OptionMeta (New-OptionMeta -Id 'poll_batch' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Batch Polling' -Type 'combo' -Flag '--poll-batch' -Choices @('0', '1') -Default '0' -Tooltip 'Batch polling toggle.')
Add-OptionMeta (New-OptionMeta -Id 'ctx_size' -Tab 'Performance' -Section 'Context and Memory' -Label 'Context Size' -Type 'number' -Flag '--ctx-size' -Default 0 -Min 0 -Max 1048576 -Basic $true -Tooltip "This is the model's working memory window: how much earlier text it can keep in mind at once.`n`nRecommendation: leave this unchecked first so llama-server can use the model's own metadata. Modern families like Gemma 3, Mistral Small 3.1, Llama 4, Qwen3, and DeepSeek-style models often ship with very large native context windows, but larger context also uses much more RAM or VRAM.`n`nIf you need a manual override, 4096 or 8192 is a practical starting point for general chat.")
Add-OptionMeta (New-OptionMeta -Id 'predict' -Tab 'Performance' -Section 'Context and Memory' -Label 'Predict Tokens' -Type 'number' -Flag '--predict' -Default -1 -Min -1 -Max 1000000 -Tooltip 'Tokens to predict. -1 means unlimited.')
Add-OptionMeta (New-OptionMeta -Id 'keep' -Tab 'Performance' -Section 'Context and Memory' -Label 'Keep Tokens' -Type 'number' -Flag '--keep' -Default 0 -Min -1 -Max 1000000 -Tooltip 'Tokens kept from the initial prompt.')
Add-OptionMeta (New-OptionMeta -Id 'batch_size' -Tab 'Performance' -Section 'Context and Memory' -Label 'Batch Size' -Type 'number' -Flag '--batch-size' -Default 2048 -Min 1 -Max 65536 -Basic $true -Tooltip "Controls how many prompt tokens llama-server tries to process together while reading the prompt.`n`nRecommendation: leave this unchecked first. Increase it only when you are tuning throughput on strong hardware. Lower it if loading long prompts causes memory pressure.")
Add-OptionMeta (New-OptionMeta -Id 'ubatch_size' -Tab 'Performance' -Section 'Context and Memory' -Label 'Micro Batch Size' -Type 'number' -Flag '--ubatch-size' -Default 512 -Min 1 -Max 65536 -Tooltip 'Physical maximum batch size.')
Add-OptionMeta (New-OptionMeta -Id 'swa_full' -Tab 'Performance' -Section 'Context and Memory' -Label 'Full-size SWA Cache' -Type 'flag' -Flag '--swa-full' -Tooltip 'Use full-size SWA cache.')
Add-OptionMeta (New-OptionMeta -Id 'flash_attn' -Tab 'Performance' -Section 'Context and Memory' -Label 'Flash Attention' -Type 'combo' -Flag '--flash-attn' -Choices @('auto', 'on', 'off') -Default 'auto' -Basic $true -Tooltip "Uses a newer, faster attention path on supported hardware.`n`nRecommendation: if you override this at all, start with Auto. That is the safest modern choice, especially for newer long-context families and supported GPUs.")
Add-OptionMeta (New-OptionMeta -Id 'perf' -Tab 'Performance' -Section 'Context and Memory' -Label 'libllama Perf Timings' -Type 'pair' -Flag '--perf' -NegFlag '--no-perf' -Default 'Enabled' -Tooltip 'Force internal performance timing collection on or off.')
Add-OptionMeta (New-OptionMeta -Id 'escape' -Tab 'Performance' -Section 'Context and Memory' -Label 'Escape Sequences' -Type 'pair' -Flag '--escape' -NegFlag '--no-escape' -Default 'Enabled' -Tooltip 'Force escape sequence processing on or off.')
Add-OptionMeta (New-OptionMeta -Id 'rope_scaling' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'RoPE Scaling' -Type 'combo' -Flag '--rope-scaling' -Choices @('none', 'linear', 'yarn') -Default 'linear' -Tooltip 'RoPE scaling method.')
Add-OptionMeta (New-OptionMeta -Id 'rope_scale' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'RoPE Scale' -Type 'decimal' -Flag '--rope-scale' -Default 1.00 -Min 0.00 -Max 100.00 -Increment 0.05 -Decimals 2 -Tooltip 'RoPE context scaling factor.')
Add-OptionMeta (New-OptionMeta -Id 'rope_freq_base' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'RoPE Freq Base' -Type 'number' -Flag '--rope-freq-base' -Default 10000 -Min 0 -Max 100000000 -Tooltip 'RoPE base frequency.')
Add-OptionMeta (New-OptionMeta -Id 'rope_freq_scale' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'RoPE Freq Scale' -Type 'decimal' -Flag '--rope-freq-scale' -Default 1.00 -Min 0.00 -Max 100.00 -Increment 0.05 -Decimals 2 -Tooltip 'RoPE frequency scaling factor.')
Add-OptionMeta (New-OptionMeta -Id 'yarn_orig_ctx' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'YaRN Original Context' -Type 'number' -Flag '--yarn-orig-ctx' -Default 0 -Min 0 -Max 1048576 -Tooltip 'Original context size used for YaRN.')
Add-OptionMeta (New-OptionMeta -Id 'yarn_ext_factor' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'YaRN Extrapolation Factor' -Type 'decimal' -Flag '--yarn-ext-factor' -Default -1.00 -Min -100.00 -Max 100.00 -Increment 0.05 -Decimals 2 -Tooltip 'YaRN extrapolation mix factor.')
Add-OptionMeta (New-OptionMeta -Id 'yarn_attn_factor' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'YaRN Attention Factor' -Type 'decimal' -Flag '--yarn-attn-factor' -Default -1.00 -Min -100.00 -Max 100.00 -Increment 0.05 -Decimals 2 -Tooltip 'YaRN attention scaling factor.')
Add-OptionMeta (New-OptionMeta -Id 'yarn_beta_slow' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'YaRN Beta Slow' -Type 'decimal' -Flag '--yarn-beta-slow' -Default -1.00 -Min -100.00 -Max 100.00 -Increment 0.05 -Decimals 2 -Tooltip 'YaRN beta slow.')
Add-OptionMeta (New-OptionMeta -Id 'yarn_beta_fast' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'YaRN Beta Fast' -Type 'decimal' -Flag '--yarn-beta-fast' -Default -1.00 -Min -100.00 -Max 100.00 -Increment 0.05 -Decimals 2 -Tooltip 'YaRN beta fast.')
Add-OptionMeta (New-OptionMeta -Id 'kv_offload' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'KV Offload' -Type 'pair' -Flag '--kv-offload' -NegFlag '--no-kv-offload' -Default 'Enabled' -Tooltip 'Force KV cache offloading on or off.')
Add-OptionMeta (New-OptionMeta -Id 'repack' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Weight Repacking' -Type 'pair' -Flag '--repack' -NegFlag '--no-repack' -Default 'Enabled' -Tooltip 'Force weight repacking on or off.')
Add-OptionMeta (New-OptionMeta -Id 'no_host' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Bypass Host Buffer' -Type 'flag' -Flag '--no-host' -Tooltip 'Bypass host buffer to allow extra buffers.')
Add-OptionMeta (New-OptionMeta -Id 'cache_type_k' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Cache Type K' -Type 'combo' -Flag '--cache-type-k' -Choices $cacheTypes -Default 'f16' -Tooltip 'KV cache data type for K.')
Add-OptionMeta (New-OptionMeta -Id 'cache_type_v' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Cache Type V' -Type 'combo' -Flag '--cache-type-v' -Choices $cacheTypes -Default 'q8_0' -Basic $true -Tooltip "Changes the precision of part of the KV cache, which is the memory the model uses to remember the conversation while generating.`n`nRecommendation: leave this unchecked first. People usually change this only when chasing longer context or lower VRAM use. q8_0 is a common quality-first starting override; lower-precision types can save more memory but may hurt quality sooner.")
Add-OptionMeta (New-OptionMeta -Id 'defrag_thold' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Defrag Threshold' -Type 'decimal' -Flag '--defrag-thold' -Default 0.10 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2 -Tooltip 'Deprecated KV cache defragmentation threshold.')
Add-OptionMeta (New-OptionMeta -Id 'mlock' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Lock in RAM' -Type 'flag' -Flag '--mlock' -Tooltip 'Keep model in RAM instead of swapping/compressing.')
Add-OptionMeta (New-OptionMeta -Id 'mmap' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Memory Map Model' -Type 'pair' -Flag '--mmap' -NegFlag '--no-mmap' -Default 'Enabled' -Tooltip 'Force mmap on or off.')
Add-OptionMeta (New-OptionMeta -Id 'direct_io' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Direct I/O' -Type 'pair' -Flag '--direct-io' -NegFlag '--no-direct-io' -Default 'Enabled' -Tooltip 'Force Direct I/O on or off.')
Add-OptionMeta (New-OptionMeta -Id 'numa' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'NUMA Strategy' -Type 'combo' -Flag '--numa' -Choices @('distribute', 'isolate', 'numactl') -Default 'distribute' -Tooltip 'NUMA optimization strategy.')
Add-OptionMeta (New-OptionMeta -Id 'device' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Device(s)' -Type 'text' -Flag '--device' -Tooltip 'Comma-separated device list, for example CUDA0,CUDA1.')
Add-OptionMeta (New-OptionMeta -Id 'override_tensor' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Override Tensor Buffer' -Type 'text' -Flag '--override-tensor' -Tooltip 'tensor_name_pattern=buffer_type,...')
Add-OptionMeta (New-OptionMeta -Id 'cpu_moe' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Keep All MoE on CPU' -Type 'flag' -Flag '--cpu-moe' -Tooltip 'Keep all Mixture of Experts weights on CPU.')
Add-OptionMeta (New-OptionMeta -Id 'n_cpu_moe' -Tab 'Performance' -Section 'Devices and Offload' -Label 'CPU MoE Layers' -Type 'number' -Flag '--n-cpu-moe' -Default 0 -Min 0 -Max 10000 -Tooltip 'Keep first N MoE layers on CPU.')
Add-OptionMeta (New-OptionMeta -Id 'n_gpu_layers' -Tab 'Performance' -Section 'Devices and Offload' -Label 'GPU Layers' -Type 'combo' -Flag '--n-gpu-layers' -Choices @('auto', 'all', '0', '16', '32', '64', '99', '999') -Default 'auto' -Editable $true -Basic $true -Tooltip "Controls how much of the model is placed on the GPU instead of the CPU.`n`nRecommendation: Auto is the best first try on most systems. Use 0 only if you intentionally want CPU-only inference. Use an exact number only when you are fine-tuning memory usage by hand.")
Add-OptionMeta (New-OptionMeta -Id 'split_mode' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Split Mode' -Type 'combo' -Flag '--split-mode' -Choices @('none', 'layer', 'row') -Default 'layer' -Tooltip 'How to split across GPUs.')
Add-OptionMeta (New-OptionMeta -Id 'tensor_split' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Tensor Split' -Type 'text' -Flag '--tensor-split' -Tooltip 'Comma-separated GPU proportions, for example 3,1.')
Add-OptionMeta (New-OptionMeta -Id 'main_gpu' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Main GPU' -Type 'number' -Flag '--main-gpu' -Default 0 -Min 0 -Max 32 -Tooltip 'Main GPU index.')
Add-OptionMeta (New-OptionMeta -Id 'fit' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Auto Fit to Memory' -Type 'combo' -Flag '--fit' -Choices @('on', 'off') -Default 'on' -Basic $true -Tooltip "Lets llama-server fit the model into available memory more intelligently.`n`nRecommendation: On is a very good modern starting point and is especially helpful when you want GPU offload without manually counting layers.")
Add-OptionMeta (New-OptionMeta -Id 'fit_target' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Fit Target (MiB)' -Type 'text' -Flag '--fit-target' -Tooltip 'Comma-separated device margins in MiB.')
Add-OptionMeta (New-OptionMeta -Id 'fit_ctx' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Fit Minimum Context' -Type 'number' -Flag '--fit-ctx' -Default 4096 -Min 0 -Max 1048576 -Tooltip 'Minimum context size for --fit.')
Add-OptionMeta (New-OptionMeta -Id 'check_tensors' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Check Tensors' -Type 'flag' -Flag '--check-tensors' -Tooltip 'Check model tensor data for invalid values.')
Add-OptionMeta (New-OptionMeta -Id 'override_kv' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Override KV Metadata' -Type 'text' -Flag '--override-kv' -Tooltip 'KEY=TYPE:VALUE,...')
Add-OptionMeta (New-OptionMeta -Id 'op_offload' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Host Tensor Op Offload' -Type 'pair' -Flag '--op-offload' -NegFlag '--no-op-offload' -Default 'Enabled' -Tooltip 'Force host tensor operation offload on or off.')
Add-OptionMeta (New-OptionMeta -Id 'lora' -Tab 'Performance' -Section 'Adapters and Control Vectors' -Label 'LoRA Adapter(s)' -Type 'text' -Flag '--lora' -Tooltip 'Comma-separated LoRA adapter paths.')
Add-OptionMeta (New-OptionMeta -Id 'lora_scaled' -Tab 'Performance' -Section 'Adapters and Control Vectors' -Label 'Scaled LoRA Adapter(s)' -Type 'text' -Flag '--lora-scaled' -Tooltip 'FNAME:SCALE,...')
Add-OptionMeta (New-OptionMeta -Id 'control_vector' -Tab 'Performance' -Section 'Adapters and Control Vectors' -Label 'Control Vector(s)' -Type 'text' -Flag '--control-vector' -Tooltip 'Comma-separated control vector paths.')
Add-OptionMeta (New-OptionMeta -Id 'control_vector_scaled' -Tab 'Performance' -Section 'Adapters and Control Vectors' -Label 'Scaled Control Vector(s)' -Type 'text' -Flag '--control-vector-scaled' -Tooltip 'FNAME:SCALE,...')
Add-OptionMeta (New-OptionMeta -Id 'control_vector_layer_range' -Tab 'Performance' -Section 'Adapters and Control Vectors' -Label 'Control Vector Layer Range' -Type 'text' -Flag '--control-vector-layer-range' -Tooltip 'Enter START END.')

Add-OptionMeta (New-OptionMeta -Id 'samplers' -Tab 'Sampling' -Section 'Sampler Order' -Label 'Samplers' -Type 'text' -Flag '--samplers' -Tooltip 'Semicolon-separated sampler order.')
Add-OptionMeta (New-OptionMeta -Id 'sampler_seq' -Tab 'Sampling' -Section 'Sampler Order' -Label 'Sampler Sequence' -Type 'text' -Flag '--sampler-seq' -Tooltip 'Short sampler sequence string.')
Add-OptionMeta (New-OptionMeta -Id 'seed' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Seed' -Type 'number' -Flag '--seed' -Default -1 -Min -1 -Max 2147483647 -Basic $true -Tooltip "A seed is the random starting point for sampling.`n`nRecommendation: leave this unchecked for normal chatting. Use a fixed seed only when you want repeatable tests or side-by-side comparisons.")
Add-OptionMeta (New-OptionMeta -Id 'ignore_eos' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Ignore EOS' -Type 'flag' -Flag '--ignore-eos' -Tooltip 'Ignore end-of-stream token.')
Add-OptionMeta (New-OptionMeta -Id 'temp' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Temperature' -Type 'decimal' -Flag '--temp' -Default 0.70 -Min 0.00 -Max 10.00 -Increment 0.05 -Decimals 2 -Basic $true -Tooltip "Controls how bold or conservative the next-token choice feels.`n`nRecommendation: 0.7 is a strong modern starting point. Lower values are steadier and more exact; higher values are more creative. Recent Qwen3 instruct cards recommend cooler settings such as 0.7, and reasoning-heavy families often behave better when you do not push temperature too high.")
Add-OptionMeta (New-OptionMeta -Id 'top_k' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Top-K' -Type 'number' -Flag '--top-k' -Default 20 -Min 0 -Max 100000 -Basic $true -Tooltip "Limits the choice list to the top K candidate tokens before sampling.`n`nRecommendation: leave this unchecked unless you are intentionally tuning style. If you do tune it, 20 is a strong modern starting point and lines up with current Qwen3 guidance.")
Add-OptionMeta (New-OptionMeta -Id 'top_p' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Top-P' -Type 'decimal' -Flag '--top-p' -Default 0.90 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2 -Basic $true -Tooltip "Keeps enough candidate tokens to cover a chosen probability mass.`n`nRecommendation: 0.9 is a good all-around starting point. Some current model cards, especially in the Qwen3 family, recommend even tighter settings such as 0.8 for more disciplined output.")
Add-OptionMeta (New-OptionMeta -Id 'min_p' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Min-P' -Type 'decimal' -Flag '--min-p' -Default 0.00 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2 -Basic $true -Tooltip "Drops token choices that are too weak compared with the best option.`n`nRecommendation: 0.00 is the safest starting point because it effectively leaves Min-P out of the way. Raise it only when you want stricter filtering.")
Add-OptionMeta (New-OptionMeta -Id 'top_n_sigma' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Top-N Sigma' -Type 'decimal' -Flag '--top-n-sigma' -Default -1.00 -Min -10.00 -Max 10.00 -Increment 0.05 -Decimals 2 -Tooltip 'Top-N sigma sampling. -1 disables.')
Add-OptionMeta (New-OptionMeta -Id 'xtc_probability' -Tab 'Sampling' -Section 'Core Sampling' -Label 'XTC Probability' -Type 'decimal' -Flag '--xtc-probability' -Default 0.00 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2 -Tooltip 'XTC probability.')
Add-OptionMeta (New-OptionMeta -Id 'xtc_threshold' -Tab 'Sampling' -Section 'Core Sampling' -Label 'XTC Threshold' -Type 'decimal' -Flag '--xtc-threshold' -Default 0.10 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2 -Tooltip 'XTC threshold.')
Add-OptionMeta (New-OptionMeta -Id 'typical_p' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Typical-P' -Type 'decimal' -Flag '--typical-p' -Default 1.00 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2 -Tooltip 'Locally typical sampling parameter.')
Add-OptionMeta (New-OptionMeta -Id 'repeat_last_n' -Tab 'Sampling' -Section 'Penalties' -Label 'Repeat Last N' -Type 'number' -Flag '--repeat-last-n' -Default 64 -Min -1 -Max 1048576 -Tooltip 'Tokens considered for repetition penalty.')
Add-OptionMeta (New-OptionMeta -Id 'repeat_penalty' -Tab 'Sampling' -Section 'Penalties' -Label 'Repeat Penalty' -Type 'decimal' -Flag '--repeat-penalty' -Default 1.05 -Min 0.00 -Max 10.00 -Increment 0.01 -Decimals 2 -Basic $true -Tooltip "Helps reduce repetitive loops and the model repeating the same wording.`n`nRecommendation: leave this unchecked first. If the model starts looping, a gentle value such as 1.05 to 1.10 is a good first fix.")
Add-OptionMeta (New-OptionMeta -Id 'presence_penalty' -Tab 'Sampling' -Section 'Penalties' -Label 'Presence Penalty' -Type 'decimal' -Flag '--presence-penalty' -Default 0.00 -Min -5.00 -Max 5.00 -Increment 0.01 -Decimals 2 -Tooltip 'Presence penalty.')
Add-OptionMeta (New-OptionMeta -Id 'frequency_penalty' -Tab 'Sampling' -Section 'Penalties' -Label 'Frequency Penalty' -Type 'decimal' -Flag '--frequency-penalty' -Default 0.00 -Min -5.00 -Max 5.00 -Increment 0.01 -Decimals 2 -Tooltip 'Frequency penalty.')
Add-OptionMeta (New-OptionMeta -Id 'dry_multiplier' -Tab 'Sampling' -Section 'DRY and Adaptive' -Label 'DRY Multiplier' -Type 'decimal' -Flag '--dry-multiplier' -Default 0.00 -Min 0.00 -Max 10.00 -Increment 0.05 -Decimals 2 -Tooltip 'DRY sampling multiplier.')
Add-OptionMeta (New-OptionMeta -Id 'dry_base' -Tab 'Sampling' -Section 'DRY and Adaptive' -Label 'DRY Base' -Type 'decimal' -Flag '--dry-base' -Default 1.75 -Min 0.00 -Max 10.00 -Increment 0.05 -Decimals 2 -Tooltip 'DRY base value.')
Add-OptionMeta (New-OptionMeta -Id 'dry_allowed_length' -Tab 'Sampling' -Section 'DRY and Adaptive' -Label 'DRY Allowed Length' -Type 'number' -Flag '--dry-allowed-length' -Default 2 -Min 0 -Max 100000 -Tooltip 'Allowed DRY sequence length.')
Add-OptionMeta (New-OptionMeta -Id 'dry_penalty_last_n' -Tab 'Sampling' -Section 'DRY and Adaptive' -Label 'DRY Penalty Last N' -Type 'number' -Flag '--dry-penalty-last-n' -Default -1 -Min -1 -Max 1048576 -Tooltip 'Last N tokens for DRY penalty.')
Add-OptionMeta (New-OptionMeta -Id 'dry_sequence_breaker' -Tab 'Sampling' -Section 'DRY and Adaptive' -Label 'DRY Sequence Breaker' -Type 'text' -Flag '--dry-sequence-breaker' -Tooltip 'Use none for no breakers, or provide a custom breaker string.')
Add-OptionMeta (New-OptionMeta -Id 'adaptive_target' -Tab 'Sampling' -Section 'DRY and Adaptive' -Label 'Adaptive Target' -Type 'decimal' -Flag '--adaptive-target' -Default -1.00 -Min -1.00 -Max 1.00 -Increment 0.01 -Decimals 2 -Tooltip 'Adaptive-p target. Negative disables.')
Add-OptionMeta (New-OptionMeta -Id 'adaptive_decay' -Tab 'Sampling' -Section 'DRY and Adaptive' -Label 'Adaptive Decay' -Type 'decimal' -Flag '--adaptive-decay' -Default 0.90 -Min 0.00 -Max 0.99 -Increment 0.01 -Decimals 2 -Tooltip 'Adaptive-p decay.')
Add-OptionMeta (New-OptionMeta -Id 'dynatemp_range' -Tab 'Sampling' -Section 'Dynamic Temperature and Mirostat' -Label 'Dynatemp Range' -Type 'decimal' -Flag '--dynatemp-range' -Default 0.00 -Min 0.00 -Max 10.00 -Increment 0.05 -Decimals 2 -Tooltip 'Dynamic temperature range.')
Add-OptionMeta (New-OptionMeta -Id 'dynatemp_exp' -Tab 'Sampling' -Section 'Dynamic Temperature and Mirostat' -Label 'Dynatemp Exponent' -Type 'decimal' -Flag '--dynatemp-exp' -Default 1.00 -Min 0.00 -Max 10.00 -Increment 0.05 -Decimals 2 -Tooltip 'Dynamic temperature exponent.')
Add-OptionMeta (New-OptionMeta -Id 'mirostat' -Tab 'Sampling' -Section 'Dynamic Temperature and Mirostat' -Label 'Mirostat Mode' -Type 'combo' -Flag '--mirostat' -Choices @('0', '1', '2') -Default '0' -Tooltip '0 disables, 1 = Mirostat, 2 = Mirostat 2.0.')
Add-OptionMeta (New-OptionMeta -Id 'mirostat_lr' -Tab 'Sampling' -Section 'Dynamic Temperature and Mirostat' -Label 'Mirostat Learning Rate' -Type 'decimal' -Flag '--mirostat-lr' -Default 0.10 -Min 0.00 -Max 10.00 -Increment 0.01 -Decimals 2 -Tooltip 'Mirostat eta.')
Add-OptionMeta (New-OptionMeta -Id 'mirostat_ent' -Tab 'Sampling' -Section 'Dynamic Temperature and Mirostat' -Label 'Mirostat Target Entropy' -Type 'decimal' -Flag '--mirostat-ent' -Default 5.00 -Min 0.00 -Max 20.00 -Increment 0.05 -Decimals 2 -Tooltip 'Mirostat tau.')
Add-OptionMeta (New-OptionMeta -Id 'logit_bias' -Tab 'Sampling' -Section 'Constraints' -Label 'Logit Bias' -Type 'text' -Flag '--logit-bias' -Tooltip 'TOKEN_ID(+/-)BIAS.')
Add-OptionMeta (New-OptionMeta -Id 'grammar' -Tab 'Sampling' -Section 'Constraints' -Label 'Grammar' -Type 'text' -Flag '--grammar' -Tooltip 'Inline GBNF grammar string.')
Add-OptionMeta (New-OptionMeta -Id 'grammar_file' -Tab 'Sampling' -Section 'Constraints' -Label 'Grammar File' -Type 'path' -Flag '--grammar-file' -BrowseMode 'file' -Filter 'Grammar files (*.gbnf)|*.gbnf|All files (*.*)|*.*' -Tooltip 'Path to a GBNF grammar file.')
Add-OptionMeta (New-OptionMeta -Id 'json_schema' -Tab 'Sampling' -Section 'Constraints' -Label 'JSON Schema' -Type 'text' -Flag '--json-schema' -Tooltip 'Inline JSON schema.')
Add-OptionMeta (New-OptionMeta -Id 'json_schema_file' -Tab 'Sampling' -Section 'Constraints' -Label 'JSON Schema File' -Type 'path' -Flag '--json-schema-file' -BrowseMode 'file' -Filter 'JSON files (*.json)|*.json|All files (*.*)|*.*' -Tooltip 'Path to a JSON schema file.')
Add-OptionMeta (New-OptionMeta -Id 'backend_sampling' -Tab 'Sampling' -Section 'Constraints' -Label 'Backend Sampling' -Type 'flag' -Flag '--backend-sampling' -Tooltip 'Enable experimental backend sampling.')

Add-OptionMeta (New-OptionMeta -Id 'reverse_prompt' -Tab 'Chat' -Section 'Prompt and Parsing' -Label 'Reverse Prompt' -Type 'text' -Flag '--reverse-prompt' -Tooltip 'Stop generation at this prompt in interactive mode.')
Add-OptionMeta (New-OptionMeta -Id 'special' -Tab 'Chat' -Section 'Prompt and Parsing' -Label 'Special Tokens Output' -Type 'flag' -Flag '--special' -Tooltip 'Allow special tokens in output.')
Add-OptionMeta (New-OptionMeta -Id 'pooling' -Tab 'Chat' -Section 'Embeddings and Reranking' -Label 'Pooling' -Type 'combo' -Flag '--pooling' -Choices @('none', 'mean', 'cls', 'last', 'rank') -Default 'mean' -Tooltip 'Pooling type for embeddings.')
Add-OptionMeta (New-OptionMeta -Id 'embedding' -Tab 'Chat' -Section 'Embeddings and Reranking' -Label 'Embedding-only Mode' -Type 'flag' -Flag '--embedding' -Tooltip 'Restrict server to embeddings use case.')
Add-OptionMeta (New-OptionMeta -Id 'reranking' -Tab 'Chat' -Section 'Embeddings and Reranking' -Label 'Reranking Endpoint' -Type 'flag' -Flag '--reranking' -Tooltip 'Enable reranking endpoint.')
Add-OptionMeta (New-OptionMeta -Id 'jinja' -Tab 'Chat' -Section 'Templates and Reasoning' -Label 'Jinja Engine' -Type 'pair' -Flag '--jinja' -NegFlag '--no-jinja' -Default 'Enabled' -Basic $true -Tooltip "Jinja is the modern chat-template engine used by many current instruct models.`n`nRecommendation: leave this unchecked unless the model is formatting replies incorrectly, tool calling is broken, or a model card tells you to change template behavior. When you do override it, Enabled is usually correct for newer families.")
Add-OptionMeta (New-OptionMeta -Id 'reasoning_format' -Tab 'Chat' -Section 'Templates and Reasoning' -Label 'Reasoning Format' -Type 'combo' -Flag '--reasoning-format' -Choices @('auto', 'none', 'deepseek', 'deepseek-legacy') -Default 'auto' -Basic $true -Tooltip "Tells llama-server how to interpret visible thinking tags in the model's output.`n`nRecommendation: Auto is the safest first choice. Use DeepSeek when the model family emits DeepSeek-style reasoning tags. Use DeepSeek Legacy only for older outputs where you want to keep the tags in the visible content as well.")
Add-OptionMeta (New-OptionMeta -Id 'reasoning' -Tab 'Chat' -Section 'Templates and Reasoning' -Label 'Reasoning / Thinking' -Type 'combo' -Flag '--reasoning' -Choices @('auto', 'on', 'off') -Default 'auto' -Basic $true -Tooltip "Controls whether thinking-capable models are allowed to use their reasoning path.`n`nRecommendation: Auto is the safest first choice. Some newer models, such as Qwen thinking variants and DeepSeek-style reasoning models, expect reasoning-aware behavior. Turn it Off only if you specifically want direct answers without visible thinking support.`n`nDeepSeek-R1 style guidance also prefers putting instructions in the user message instead of relying on a system prompt.")
Add-OptionMeta (New-OptionMeta -Id 'reasoning_budget' -Tab 'Chat' -Section 'Templates and Reasoning' -Label 'Reasoning Budget' -Type 'number' -Flag '--reasoning-budget' -Default -1 -Min -1 -Max 1000000 -Basic $true -Tooltip "Limits how many tokens a reasoning model may spend thinking before the final answer.`n`nRecommendation: leave this unchecked unless you are deliberately tuning a reasoning model. -1 means unrestricted. Lower values can save time and memory, but they can also make hard reasoning tasks worse.")
Add-OptionMeta (New-OptionMeta -Id 'reasoning_budget_message' -Tab 'Chat' -Section 'Templates and Reasoning' -Label 'Reasoning Budget Message' -Type 'text' -Flag '--reasoning-budget-message' -Tooltip 'Injected message when reasoning budget is exhausted.')
Add-OptionMeta (New-OptionMeta -Id 'chat_template' -Tab 'Chat' -Section 'Templates and Reasoning' -Label 'Chat Template' -Type 'combo' -Flag '--chat-template' -Choices $chatTemplates -Default 'chatml' -Editable $true -Basic $true -Tooltip "The chat template is the formatting recipe that turns your messages into the model's prompt.`n`nRecommendation: leave this unchecked unless the model answers strangely, ignores roles, breaks tool calls, or the model card tells you which template to use. The wrong template is a very common cause of bad outputs.`n`nExamples: newer families often need family-specific templates such as llama4, gemma, deepseek, or mistral-v7-tekken.")
Add-OptionMeta (New-OptionMeta -Id 'chat_template_file' -Tab 'Chat' -Section 'Templates and Reasoning' -Label 'Chat Template File' -Type 'path' -Flag '--chat-template-file' -BrowseMode 'file' -Filter 'Template files (*.jinja;*.txt)|*.jinja;*.txt|All files (*.*)|*.*' -Tooltip 'Path to a custom chat template file.')
Add-OptionMeta (New-OptionMeta -Id 'chat_template_kwargs' -Tab 'Chat' -Section 'Templates and Reasoning' -Label 'Chat Template Kwargs JSON' -Type 'text' -Flag '--chat-template-kwargs' -Tooltip 'Additional JSON kwargs for template parsing.')
Add-OptionMeta (New-OptionMeta -Id 'skip_chat_parsing' -Tab 'Chat' -Section 'Templates and Reasoning' -Label 'Skip Chat Parsing' -Type 'pair' -Flag '--skip-chat-parsing' -NegFlag '--no-skip-chat-parsing' -Default 'Enabled' -Tooltip 'Force pure content parsing on or off.')
Add-OptionMeta (New-OptionMeta -Id 'prefill_assistant' -Tab 'Chat' -Section 'Templates and Reasoning' -Label 'Prefill Assistant' -Type 'pair' -Flag '--prefill-assistant' -NegFlag '--no-prefill-assistant' -Default 'Enabled' -Tooltip 'Control assistant prefill behavior.')
Add-OptionMeta (New-OptionMeta -Id 'lora_init_without_apply' -Tab 'Chat' -Section 'Templates and Reasoning' -Label 'LoRA Init Without Apply' -Type 'flag' -Flag '--lora-init-without-apply' -Tooltip 'Load LoRAs without applying them.')

Add-OptionMeta (New-OptionMeta -Id 'mmproj' -Tab 'Multimodal' -Section 'Projector and Vision' -Label 'Multimodal Projector' -Type 'path' -Flag '--mmproj' -BrowseMode 'file' -Filter 'GGUF files (*.gguf)|*.gguf|All files (*.*)|*.*' -Basic $true -Tooltip "Needed only for vision or multimodal model packages that ship a separate projector file.`n`nRecommendation: ignore this for normal text-only models. Use it only when your model download explicitly includes an mmproj file or the model card tells you to. This commonly matters for some Gemma 3, Mistral Small 3.1, Llama 4, and Qwen vision-style exports.`n`nIf you use --hf-repo, llama.cpp can often download the projector automatically when the repo includes one.")
Add-OptionMeta (New-OptionMeta -Id 'mmproj_url' -Tab 'Multimodal' -Section 'Projector and Vision' -Label 'Projector URL' -Type 'text' -Flag '--mmproj-url' -Tooltip 'URL to a multimodal projector file.')
Add-OptionMeta (New-OptionMeta -Id 'mmproj_auto' -Tab 'Multimodal' -Section 'Projector and Vision' -Label 'Projector Auto-Use' -Type 'pair' -Flag '--mmproj-auto' -NegFlag '--no-mmproj' -Default 'Enabled' -Tooltip 'Force projector auto-use on or off.')
Add-OptionMeta (New-OptionMeta -Id 'mmproj_offload' -Tab 'Multimodal' -Section 'Projector and Vision' -Label 'Projector GPU Offload' -Type 'pair' -Flag '--mmproj-offload' -NegFlag '--no-mmproj-offload' -Default 'Enabled' -Tooltip 'Force projector GPU offload on or off.')
Add-OptionMeta (New-OptionMeta -Id 'image_min_tokens' -Tab 'Multimodal' -Section 'Projector and Vision' -Label 'Image Min Tokens' -Type 'number' -Flag '--image-min-tokens' -Default 0 -Min 0 -Max 1000000 -Tooltip 'Minimum tokens per image for dynamic-resolution vision models.')
Add-OptionMeta (New-OptionMeta -Id 'image_max_tokens' -Tab 'Multimodal' -Section 'Projector and Vision' -Label 'Image Max Tokens' -Type 'number' -Flag '--image-max-tokens' -Default 0 -Min 0 -Max 1000000 -Tooltip 'Maximum tokens per image for dynamic-resolution vision models.')
Add-OptionMeta (New-OptionMeta -Id 'model_vocoder' -Tab 'Multimodal' -Section 'Audio and Vocoder' -Label 'Vocoder Model' -Type 'path' -Flag '--model-vocoder' -BrowseMode 'file' -Filter 'GGUF files (*.gguf)|*.gguf|All files (*.*)|*.*' -Tooltip 'Path to a vocoder model.')
Add-OptionMeta (New-OptionMeta -Id 'hf_repo_v' -Tab 'Multimodal' -Section 'Audio and Vocoder' -Label 'HF Repo (Vocoder)' -Type 'text' -Flag '--hf-repo-v' -Tooltip 'Hugging Face repo for the vocoder model.')
Add-OptionMeta (New-OptionMeta -Id 'hf_file_v' -Tab 'Multimodal' -Section 'Audio and Vocoder' -Label 'HF File (Vocoder)' -Type 'text' -Flag '--hf-file-v' -Tooltip 'Specific Hugging Face file for the vocoder model.')
Add-OptionMeta (New-OptionMeta -Id 'tts_use_guide_tokens' -Tab 'Multimodal' -Section 'Audio and Vocoder' -Label 'TTS Guide Tokens' -Type 'flag' -Flag '--tts-use-guide-tokens' -Tooltip 'Use guide tokens for better TTS word recall.')

Add-OptionMeta (New-OptionMeta -Id 'lookup_cache_static' -Tab 'Speculative' -Section 'Lookup and Draft Cache' -Label 'Static Lookup Cache' -Type 'path' -Flag '--lookup-cache-static' -BrowseMode 'file' -Filter 'All files (*.*)|*.*' -Tooltip 'Path to a static lookup cache file.')
Add-OptionMeta (New-OptionMeta -Id 'lookup_cache_dynamic' -Tab 'Speculative' -Section 'Lookup and Draft Cache' -Label 'Dynamic Lookup Cache' -Type 'path' -Flag '--lookup-cache-dynamic' -BrowseMode 'file' -Filter 'All files (*.*)|*.*' -Tooltip 'Path to a dynamic lookup cache file.')
Add-OptionMeta (New-OptionMeta -Id 'cache_type_k_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft Cache Type K' -Type 'combo' -Flag '--cache-type-k-draft' -Choices $cacheTypes -Default 'f16' -Tooltip 'Draft model KV cache type for K.')
Add-OptionMeta (New-OptionMeta -Id 'cache_type_v_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft Cache Type V' -Type 'combo' -Flag '--cache-type-v-draft' -Choices $cacheTypes -Default 'f16' -Tooltip 'Draft model KV cache type for V.')
Add-OptionMeta (New-OptionMeta -Id 'hf_repo_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'HF Repo (Draft)' -Type 'text' -Flag '--hf-repo-draft' -Tooltip 'Hugging Face repo for the draft model.')
Add-OptionMeta (New-OptionMeta -Id 'override_tensor_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Override Tensor Buffer (Draft)' -Type 'text' -Flag '--override-tensor-draft' -Tooltip 'tensor_name_pattern=buffer_type,... for draft model.')
Add-OptionMeta (New-OptionMeta -Id 'cpu_moe_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Keep All Draft MoE on CPU' -Type 'flag' -Flag '--cpu-moe-draft' -Tooltip 'Keep all draft Mixture of Experts weights on CPU.')
Add-OptionMeta (New-OptionMeta -Id 'n_cpu_moe_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft CPU MoE Layers' -Type 'number' -Flag '--n-cpu-moe-draft' -Default 0 -Min 0 -Max 10000 -Tooltip 'Keep first N draft MoE layers on CPU.')
Add-OptionMeta (New-OptionMeta -Id 'threads_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft Threads' -Type 'number' -Flag '--threads-draft' -Default -1 -Min -1 -Max 256 -Tooltip 'Draft generation threads.')
Add-OptionMeta (New-OptionMeta -Id 'threads_batch_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft Batch Threads' -Type 'number' -Flag '--threads-batch-draft' -Default -1 -Min -1 -Max 256 -Tooltip 'Draft batch and prompt processing threads.')
Add-OptionMeta (New-OptionMeta -Id 'draft_max' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Draft Tokens' -Type 'number' -Flag '--draft' -Default 16 -Min 0 -Max 100000 -Tooltip 'Number of tokens to draft.')
Add-OptionMeta (New-OptionMeta -Id 'draft_min' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Draft Min Tokens' -Type 'number' -Flag '--draft-min' -Default 0 -Min 0 -Max 100000 -Tooltip 'Minimum draft tokens to use.')
Add-OptionMeta (New-OptionMeta -Id 'draft_p_min' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Draft Min Probability' -Type 'decimal' -Flag '--draft-p-min' -Default 0.75 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2 -Tooltip 'Minimum speculative decoding probability.')
Add-OptionMeta (New-OptionMeta -Id 'ctx_size_draft' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Draft Context Size' -Type 'number' -Flag '--ctx-size-draft' -Default 0 -Min 0 -Max 1048576 -Tooltip 'Draft model context size. 0 uses model metadata.')
Add-OptionMeta (New-OptionMeta -Id 'device_draft' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Draft Device(s)' -Type 'text' -Flag '--device-draft' -Tooltip 'Comma-separated devices for draft model offload.')
Add-OptionMeta (New-OptionMeta -Id 'n_gpu_layers_draft' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Draft GPU Layers' -Type 'combo' -Flag '--n-gpu-layers-draft' -Choices @('auto', 'all', '0', '16', '32', '64', '99', '999') -Default 'auto' -Editable $true -Tooltip 'Exact number, auto, or all for the draft model.')
Add-OptionMeta (New-OptionMeta -Id 'model_draft' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Draft Model' -Type 'path' -Flag '--model-draft' -BrowseMode 'file' -Filter 'GGUF files (*.gguf)|*.gguf|All files (*.*)|*.*' -Tooltip 'Path to the draft model.')
Add-OptionMeta (New-OptionMeta -Id 'spec_replace' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Spec Replace' -Type 'text' -Flag '--spec-replace' -Tooltip 'Enter TARGET DRAFT.')
Add-OptionMeta (New-OptionMeta -Id 'spec_type' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Spec Type' -Type 'combo' -Flag '--spec-type' -Choices @('none', 'ngram-cache', 'ngram-simple', 'ngram-map-k', 'ngram-map-k4v', 'ngram-mod') -Default 'none' -Tooltip 'Speculative decoding mode when no draft model is provided.')
Add-OptionMeta (New-OptionMeta -Id 'spec_ngram_size_n' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Spec N-gram Size N' -Type 'number' -Flag '--spec-ngram-size-n' -Default 12 -Min 1 -Max 1000 -Tooltip 'Lookup n-gram length.')
Add-OptionMeta (New-OptionMeta -Id 'spec_ngram_size_m' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Spec N-gram Size M' -Type 'number' -Flag '--spec-ngram-size-m' -Default 48 -Min 1 -Max 1000 -Tooltip 'Draft m-gram length.')
Add-OptionMeta (New-OptionMeta -Id 'spec_ngram_min_hits' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Spec N-gram Min Hits' -Type 'number' -Flag '--spec-ngram-min-hits' -Default 1 -Min 1 -Max 100000 -Tooltip 'Minimum hits for n-gram map speculative decoding.')

Add-OptionMeta (New-OptionMeta -Id 'ctx_checkpoints' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Context Checkpoints' -Type 'number' -Flag '--ctx-checkpoints' -Default 32 -Min 0 -Max 100000 -Tooltip 'Max checkpoints per slot.')
Add-OptionMeta (New-OptionMeta -Id 'checkpoint_every_tokens' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Checkpoint Every N Tokens' -Type 'number' -Flag '--checkpoint-every-n-tokens' -Default 8192 -Min -1 -Max 1000000 -Tooltip 'Create checkpoints during prefill. -1 disables.')
Add-OptionMeta (New-OptionMeta -Id 'cache_ram' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Cache RAM (MiB)' -Type 'number' -Flag '--cache-ram' -Default 8192 -Min -1 -Max 1048576 -Tooltip 'Maximum cache size in MiB. -1 removes the limit.')
Add-OptionMeta (New-OptionMeta -Id 'kv_unified' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Unified KV Buffer' -Type 'pair' -Flag '--kv-unified' -NegFlag '--no-kv-unified' -Default 'Enabled' -Tooltip 'Force unified KV buffer on or off.')
Add-OptionMeta (New-OptionMeta -Id 'clear_idle' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Clear Idle Slots' -Type 'pair' -Flag '--clear-idle' -NegFlag '--no-clear-idle' -Default 'Enabled' -Tooltip 'Save and clear idle slots on new task.')
Add-OptionMeta (New-OptionMeta -Id 'context_shift' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Context Shift' -Type 'pair' -Flag '--context-shift' -NegFlag '--no-context-shift' -Default 'Enabled' -Tooltip 'Force context shift on or off.')
Add-OptionMeta (New-OptionMeta -Id 'warmup' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Warmup' -Type 'pair' -Flag '--warmup' -NegFlag '--no-warmup' -Default 'Enabled' -Tooltip 'Force warmup on or off.')
Add-OptionMeta (New-OptionMeta -Id 'spm_infill' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'SPM Infill Pattern' -Type 'flag' -Flag '--spm-infill' -Tooltip 'Use Suffix/Prefix/Middle pattern for infill.')
Add-OptionMeta (New-OptionMeta -Id 'parallel' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Parallel Slots' -Type 'number' -Flag '--parallel' -Default -1 -Min -1 -Max 1024 -Tooltip 'Number of server slots. -1 uses auto.')
Add-OptionMeta (New-OptionMeta -Id 'cont_batching' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Continuous Batching' -Type 'pair' -Flag '--cont-batching' -NegFlag '--no-cont-batching' -Default 'Enabled' -Tooltip 'Force continuous batching on or off.')
Add-OptionMeta (New-OptionMeta -Id 'cache_prompt' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Prompt Cache' -Type 'pair' -Flag '--cache-prompt' -NegFlag '--no-cache-prompt' -Default 'Enabled' -Tooltip 'Force prompt caching on or off.')
Add-OptionMeta (New-OptionMeta -Id 'cache_reuse' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Cache Reuse Chunk Size' -Type 'number' -Flag '--cache-reuse' -Default 0 -Min 0 -Max 1000000 -Tooltip 'Minimum chunk size for cache reuse via KV shifting.')
Add-OptionMeta (New-OptionMeta -Id 'slot_prompt_similarity' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Slot Prompt Similarity' -Type 'decimal' -Flag '--slot-prompt-similarity' -Default 0.10 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2 -Tooltip 'Prompt similarity threshold for slot reuse.')
Add-OptionMeta (New-OptionMeta -Id 'sleep_idle_seconds' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Sleep Idle Seconds' -Type 'number' -Flag '--sleep-idle-seconds' -Default -1 -Min -1 -Max 86400 -Tooltip 'Seconds of idleness before sleeping. -1 disables.')
Add-OptionMeta (New-OptionMeta -Id 'models_dir' -Tab 'Router' -Section 'Router Mode' -Label 'Models Directory' -Type 'folder' -Flag '--models-dir' -BrowseMode 'folder' -Basic $true -Tooltip "A folder that router mode scans for models.`n`nRecommendation: this is the easiest way to start with router mode when you want one server that can discover multiple local models.")
Add-OptionMeta (New-OptionMeta -Id 'models_preset' -Tab 'Router' -Section 'Router Mode' -Label 'Models Preset File' -Type 'path' -Flag '--models-preset' -BrowseMode 'file' -Filter 'INI files (*.ini)|*.ini|All files (*.*)|*.*' -Basic $true -Tooltip "An INI file that describes router model presets.`n`nRecommendation: use this when you already have a preset file. Otherwise, Models Directory is usually the simpler beginner path.")
Add-OptionMeta (New-OptionMeta -Id 'models_max' -Tab 'Router' -Section 'Router Mode' -Label 'Max Loaded Models' -Type 'number' -Flag '--models-max' -Default 4 -Min 0 -Max 1024 -Basic $true -Tooltip "Maximum number of router models kept loaded at once.`n`nRecommendation: 4 is a practical starting point. Lower it if RAM or VRAM is tight. Use 0 only if you intentionally want no limit.")
Add-OptionMeta (New-OptionMeta -Id 'models_autoload' -Tab 'Router' -Section 'Router Mode' -Label 'Router Autoload' -Type 'pair' -Flag '--models-autoload' -NegFlag '--no-models-autoload' -Default 'Enabled' -Basic $true -Tooltip "Controls whether router mode loads models automatically when requests need them.`n`nRecommendation: Enabled is the easiest beginner-friendly choice.")

Add-OptionMeta (New-OptionMeta -Id 'log_disable' -Tab 'Logging' -Section 'Logging' -Label 'Disable Logging' -Type 'flag' -Flag '--log-disable' -Tooltip 'Disable logging output.')
Add-OptionMeta (New-OptionMeta -Id 'log_file' -Tab 'Logging' -Section 'Logging' -Label 'Log File' -Type 'path' -Flag '--log-file' -BrowseMode 'file' -Filter 'Log files (*.log;*.txt)|*.log;*.txt|All files (*.*)|*.*' -Tooltip 'Write logs to a file.')
Add-OptionMeta (New-OptionMeta -Id 'log_colors' -Tab 'Logging' -Section 'Logging' -Label 'Log Colors' -Type 'combo' -Flag '--log-colors' -Choices @('auto', 'on', 'off') -Default 'auto' -Tooltip 'Colored logging mode.')
Add-OptionMeta (New-OptionMeta -Id 'verbose' -Tab 'Logging' -Section 'Logging' -Label 'Verbose Logging' -Type 'flag' -Flag '--verbose' -Tooltip 'Set verbosity to infinity.')
Add-OptionMeta (New-OptionMeta -Id 'verbosity' -Tab 'Logging' -Section 'Logging' -Label 'Verbosity Threshold' -Type 'combo' -Flag '--verbosity' -Choices @('0', '1', '2', '3', '4') -Default '3' -Tooltip '0 = generic, 1 = error, 2 = warning, 3 = info, 4 = debug.')
Add-OptionMeta (New-OptionMeta -Id 'log_prefix' -Tab 'Logging' -Section 'Logging' -Label 'Log Prefix' -Type 'flag' -Flag '--log-prefix' -Tooltip 'Enable log message prefixes.')
Add-OptionMeta (New-OptionMeta -Id 'log_timestamps' -Tab 'Logging' -Section 'Logging' -Label 'Log Timestamps' -Type 'flag' -Flag '--log-timestamps' -Tooltip 'Enable timestamps in log messages.')

$form = New-Object System.Windows.Forms.Form
$form.Text = 'llama-server-launcher'
$form.Size = [System.Drawing.Size]::new(1480, 1040)
$form.MinimumSize = [System.Drawing.Size]::new(1220, 820)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$script:form = $form

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'llama-server-launcher'
$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$titleLabel.Location = [System.Drawing.Point]::new(15, 12)
$titleLabel.Size = [System.Drawing.Size]::new(280, 28)
$form.Controls.Add($titleLabel)
$script:titleLabel = $titleLabel

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = 'Basic shows the settings most people actually touch. Full keeps the complete llama-server surface. Unchecked rows stay gray and are omitted from the live command.'
$subtitleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$subtitleLabel.ForeColor = [System.Drawing.Color]::Gray
$subtitleLabel.Location = [System.Drawing.Point]::new(15, 40)
$subtitleLabel.Size = [System.Drawing.Size]::new(1320, 18)
$subtitleLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($subtitleLabel)
$script:subtitleLabel = $subtitleLabel

$grpRequired = New-Object System.Windows.Forms.GroupBox
$grpRequired.Text = 'Required'
$grpRequired.Location = [System.Drawing.Point]::new(10, 62)
$grpRequired.Size = [System.Drawing.Size]::new(1340, 148)
$grpRequired.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$grpRequired.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($grpRequired)
$script:grpRequired = $grpRequired

$lblMode = New-Object System.Windows.Forms.Label
$lblMode.Text = 'Mode'
$lblMode.Location = [System.Drawing.Point]::new(12, 24)
$lblMode.Size = [System.Drawing.Size]::new(90, 20)
$lblMode.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$grpRequired.Controls.Add($lblMode)
$script:lblModeRequired = $lblMode

$cmbMode = New-Object System.Windows.Forms.ComboBox
$cmbMode.Location = [System.Drawing.Point]::new(100, 21)
$cmbMode.Size = [System.Drawing.Size]::new(190, 24)
$cmbMode.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$cmbMode.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$cmbMode.Items.Add('Single Model')
[void]$cmbMode.Items.Add('Router')
$cmbMode.SelectedItem = 'Single Model'
$grpRequired.Controls.Add($cmbMode)
$script:cmbMode = $cmbMode

$lblView = New-Object System.Windows.Forms.Label
$lblView.Text = 'View'
$lblView.Location = [System.Drawing.Point]::new(312, 24)
$lblView.Size = [System.Drawing.Size]::new(48, 20)
$lblView.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$grpRequired.Controls.Add($lblView)
$script:lblViewRequired = $lblView

$cmbView = New-Object System.Windows.Forms.ComboBox
$cmbView.Location = [System.Drawing.Point]::new(360, 21)
$cmbView.Size = [System.Drawing.Size]::new(160, 24)
$cmbView.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$cmbView.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$cmbView.Items.Add('Basic')
[void]$cmbView.Items.Add('Full')
$cmbView.SelectedItem = 'Basic'
$grpRequired.Controls.Add($cmbView)
$script:cmbView = $cmbView

$lblServer = New-Object System.Windows.Forms.Label
$lblServer.Text = 'llama-server.exe'
$lblServer.Location = [System.Drawing.Point]::new(12, 51)
$lblServer.Size = [System.Drawing.Size]::new(128, 20)
$lblServer.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$grpRequired.Controls.Add($lblServer)
$script:lblServerRequired = $lblServer

$txtServer = New-Object System.Windows.Forms.TextBox
$txtServer.Location = [System.Drawing.Point]::new(100, 48)
$txtServer.Size = [System.Drawing.Size]::new(1120, 24)
$txtServer.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$txtServer.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtServer.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$grpRequired.Controls.Add($txtServer)
$script:txtServer = $txtServer

$btnServer = New-Object System.Windows.Forms.Button
$btnServer.Text = 'Browse'
$btnServer.Location = [System.Drawing.Point]::new(1228, 47)
$btnServer.Size = [System.Drawing.Size]::new(92, 27)
$btnServer.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$btnServer.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$btnServer.Add_Click({
    $selected = & ${function:Browse-Path} -Title 'Select llama-server.exe' -Mode 'file' -Filter 'llama-server.exe (recommended)|llama-server.exe|Executable files (*.exe)|*.exe|All files (*.*)|*.*' -StartDir $script:BatDir
    if ($selected) {
        $script:txtServer.Text = $selected
    }
})
$grpRequired.Controls.Add($btnServer)
$script:btnServer = $btnServer

$lblModel = New-Object System.Windows.Forms.Label
$lblModel.Text = 'Model (.gguf)'
$lblModel.Location = [System.Drawing.Point]::new(12, 78)
$lblModel.Size = [System.Drawing.Size]::new(128, 20)
$lblModel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$grpRequired.Controls.Add($lblModel)
$script:lblModel = $lblModel

$txtModel = New-Object System.Windows.Forms.TextBox
$txtModel.Location = [System.Drawing.Point]::new(100, 75)
$txtModel.Size = [System.Drawing.Size]::new(1120, 24)
$txtModel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$txtModel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtModel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$grpRequired.Controls.Add($txtModel)
$script:txtModel = $txtModel

$btnModel = New-Object System.Windows.Forms.Button
$btnModel.Text = 'Browse'
$btnModel.Location = [System.Drawing.Point]::new(1228, 74)
$btnModel.Size = [System.Drawing.Size]::new(92, 27)
$btnModel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$btnModel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$btnModel.Add_Click({
    $startDir = if ($script:txtModel.Text -and (Test-Path $script:txtModel.Text)) { Split-Path -Parent $script:txtModel.Text } else { $script:BatDir }
    $selected = & ${function:Browse-Path} -Title 'Select GGUF Model' -Mode 'file' -Filter 'GGUF files (*.gguf)|*.gguf|All files (*.*)|*.*' -StartDir $startDir
    if ($selected) {
        $script:txtModel.Text = $selected
    }
})
$grpRequired.Controls.Add($btnModel)
$script:btnModel = $btnModel

$lblToolWorkingDir = New-Object System.Windows.Forms.Label
$lblToolWorkingDir.Text = 'Tool working folder'
$lblToolWorkingDir.Location = [System.Drawing.Point]::new(12, 105)
$lblToolWorkingDir.Size = [System.Drawing.Size]::new(128, 20)
$lblToolWorkingDir.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$grpRequired.Controls.Add($lblToolWorkingDir)
$script:lblToolWorkingDir = $lblToolWorkingDir

$txtToolWorkingDir = New-Object System.Windows.Forms.TextBox
$txtToolWorkingDir.Location = [System.Drawing.Point]::new(100, 102)
$txtToolWorkingDir.Size = [System.Drawing.Size]::new(1120, 24)
$txtToolWorkingDir.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$txtToolWorkingDir.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtToolWorkingDir.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$grpRequired.Controls.Add($txtToolWorkingDir)
$script:txtToolWorkingDir = $txtToolWorkingDir

$btnToolWorkingDir = New-Object System.Windows.Forms.Button
$btnToolWorkingDir.Text = 'Browse'
$btnToolWorkingDir.Location = [System.Drawing.Point]::new(1228, 101)
$btnToolWorkingDir.Size = [System.Drawing.Size]::new(92, 27)
$btnToolWorkingDir.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$btnToolWorkingDir.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$btnToolWorkingDir.Add_Click({
    $startDir = if ($script:txtToolWorkingDir.Text -and (Test-Path $script:txtToolWorkingDir.Text -PathType Container)) { $script:txtToolWorkingDir.Text } else { $script:BatDir }
    $selected = & ${function:Browse-Path} -Title 'Select tool working folder' -Mode 'folder' -Filter 'All folders|*.*' -StartDir $startDir
    if ($selected) {
        $script:txtToolWorkingDir.Text = $selected
    }
})
$grpRequired.Controls.Add($btnToolWorkingDir)
$script:btnToolWorkingDir = $btnToolWorkingDir

$requiredToolTip = New-Object System.Windows.Forms.ToolTip
$requiredToolTip.AutoPopDelay = 20000
$requiredToolTip.InitialDelay = 250
$requiredToolTip.SetToolTip($lblMode, 'Single Model launches one model. Router is the multi-model server mode.')
$requiredToolTip.SetToolTip($cmbMode, 'Single Model launches one model. Router is the multi-model server mode.')
$requiredToolTip.SetToolTip($lblView, 'Basic shows the common settings. Full shows the full upstream llama-server CLI surface.')
$requiredToolTip.SetToolTip($cmbView, 'Basic shows the common settings. Full shows the full upstream llama-server CLI surface.')
$requiredToolTip.SetToolTip($lblServer, 'Choose your llama-server.exe. If this launcher sits next to llama-server.exe, it will usually auto-fill.')
$requiredToolTip.SetToolTip($txtServer, 'Choose your llama-server.exe. If this launcher sits next to llama-server.exe, it will usually auto-fill.')
$requiredToolTip.SetToolTip($btnServer, 'Browse for llama-server.exe.')
$requiredToolTip.SetToolTip($lblModel, 'Choose a local GGUF model. Leave it blank only if you are using a checked remote model source or Router mode.')
$requiredToolTip.SetToolTip($txtModel, 'Choose a local GGUF model. Leave it blank only if you are using a checked remote model source or Router mode.')
$requiredToolTip.SetToolTip($btnModel, 'Browse for a local GGUF model file.')
$requiredToolTip.SetToolTip($lblToolWorkingDir, 'Launcher-only setting. This is the folder built-in tools and relative shell/file paths start from.')
$requiredToolTip.SetToolTip($txtToolWorkingDir, 'Launcher-only setting. Leave blank for inherited/default behavior. Set this when using built-in tools so relative paths and shell commands start from a known folder.')
$requiredToolTip.SetToolTip($btnToolWorkingDir, 'Choose the folder that built-in tools and relative shell/file paths should start from.')

$lblModeHint = New-Object System.Windows.Forms.Label
$lblModeHint.Location = [System.Drawing.Point]::new(16, 172)
$lblModeHint.Size = [System.Drawing.Size]::new(1320, 18)
$lblModeHint.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$lblModeHint.ForeColor = [System.Drawing.Color]::Gray
$lblModeHint.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($lblModeHint)
$script:lblModeHint = $lblModeHint

$mainSplit = New-Object System.Windows.Forms.SplitContainer
$mainSplit.Orientation = [System.Windows.Forms.Orientation]::Horizontal
$mainSplit.Location = [System.Drawing.Point]::new(10, 195)
$mainSplit.Size = [System.Drawing.Size]::new(1340, 735)
$mainSplit.SplitterDistance = 570
$mainSplit.SplitterWidth = 8
$mainSplit.Panel1MinSize = 300
$mainSplit.Panel2MinSize = 210
$mainSplit.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($mainSplit)
$script:mainSplit = $mainSplit

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabs.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$tabs.Add_SelectedIndexChanged({ & ${function:Update-WindowLayout} }.GetNewClosure())
$mainSplit.Panel1.Controls.Add($tabs)
$script:MainTabs = $tabs

foreach ($tabSpec in $tabSpecs) {
    $page = New-Object System.Windows.Forms.TabPage
    $page.Text = $tabSpec.Title
    $page.Tag = $tabSpec.Key
    $page.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $page.AutoScroll = $true
    $tabs.TabPages.Add($page)
    $script:TabPages[$tabSpec.Key] = $page
    $script:TabTitles[$tabSpec.Key] = $tabSpec.Title
    $script:TabLayouts[$tabSpec.Key] = [PSCustomObject]@{
        Y             = 10
        LastSection   = ''
        HeaderAdded   = $false
        UseHeader     = $null
        SettingHeader = $null
        FlagHeader    = $null
        ValueHeader   = $null
    }
    [void]$script:TabOrder.Add($tabSpec.Key)
}

$allOptionsPage = $script:TabPages['AllOptions']
$searchLabel = New-Object System.Windows.Forms.Label
$searchLabel.Text = 'Search any setting or flag, then double-click a row to jump to it.'
$searchLabel.Location = [System.Drawing.Point]::new(12, 12)
$searchLabel.Size = [System.Drawing.Size]::new(800, 18)
$searchLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$searchLabel.ForeColor = [System.Drawing.Color]::Gray
$searchLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$allOptionsPage.Controls.Add($searchLabel)

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Location = [System.Drawing.Point]::new(12, 34)
$searchBox.Size = [System.Drawing.Size]::new(360, 24)
$searchBox.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$searchBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$allOptionsPage.Controls.Add($searchBox)
$script:AllOptionsSearch = $searchBox

$allOptionsList = New-Object System.Windows.Forms.ListView
$allOptionsList.Location = [System.Drawing.Point]::new(12, 66)
$allOptionsList.Size = [System.Drawing.Size]::new(1260, 420)
$allOptionsList.View = [System.Windows.Forms.View]::Details
$allOptionsList.FullRowSelect = $true
$allOptionsList.GridLines = $true
$allOptionsList.MultiSelect = $false
$allOptionsList.HideSelection = $false
$allOptionsList.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
[void]$allOptionsList.Columns.Add('Setting', 250)
[void]$allOptionsList.Columns.Add('Flag', 260)
[void]$allOptionsList.Columns.Add('Tab', 160)
[void]$allOptionsList.Columns.Add('Status', 230)
$allOptionsPage.Controls.Add($allOptionsList)
$script:AllOptionsList = $allOptionsList

$searchBox.Add_TextChanged({ & ${function:Refresh-AllOptionsList} }.GetNewClosure())
$allOptionsList.Add_DoubleClick({
    if ($script:AllOptionsList.SelectedItems.Count -lt 1) { return }
    $selected = $script:AllOptionsList.SelectedItems[0]
    if ($selected.Tag) {
        & ${function:Jump-ToOption} -State $selected.Tag
    }
}.GetNewClosure())

foreach ($option in $script:OptionCatalog) {
    Add-OptionRow -Option $option
}

$advancedPage = $script:TabPages['Advanced']
$advancedNote = New-Object System.Windows.Forms.Label
$advancedNote.Text = 'This launcher is aligned to the current upstream llama-server README. The live preview is the source of truth for what will run.'
$advancedNote.Location = [System.Drawing.Point]::new(12, 14)
$advancedNote.Size = [System.Drawing.Size]::new(1180, 18)
$advancedNote.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$advancedNote.ForeColor = [System.Drawing.Color]::Gray
$advancedNote.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$advancedPage.Controls.Add($advancedNote)

$advancedNote2 = New-Object System.Windows.Forms.Label
$advancedNote2.Text = ('System CPU cores detected: ' + $script:CpuCores.ToString($script:InvariantCulture))
$advancedNote2.Location = [System.Drawing.Point]::new(12, 40)
$advancedNote2.Size = [System.Drawing.Size]::new(240, 18)
$advancedNote2.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$advancedPage.Controls.Add($advancedNote2)

$previewLabel = New-Object System.Windows.Forms.Label
$previewLabel.Text = 'Live command preview:'
$previewLabel.Location = [System.Drawing.Point]::new(10, 10)
$previewLabel.Size = [System.Drawing.Size]::new(260, 18)
$previewLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$previewLabel.ForeColor = [System.Drawing.Color]::Gray
$previewLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$mainSplit.Panel2.Controls.Add($previewLabel)
$script:previewLabel = $previewLabel

$txtPreview = New-Object System.Windows.Forms.TextBox
$txtPreview.Location = [System.Drawing.Point]::new(10, 32)
$txtPreview.Size = [System.Drawing.Size]::new(1318, 131)
$txtPreview.Multiline = $true
$txtPreview.ReadOnly = $true
$txtPreview.WordWrap = $false
$txtPreview.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$txtPreview.Font = New-Object System.Drawing.Font('Consolas', 9.5)
$txtPreview.BackColor = [System.Drawing.Color]::White
$txtPreview.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$mainSplit.Panel2.Controls.Add($txtPreview)
$script:txtPreview = $txtPreview

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = 'Copy Command'
$btnCopy.Location = [System.Drawing.Point]::new(10, 172)
$btnCopy.Size = [System.Drawing.Size]::new(125, 32)
$btnCopy.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$btnCopy.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnCopy.Add_Click({
    [System.Windows.Forms.Clipboard]::SetText((& ${function:Get-FlatCommandText}))
    $btnCopy.Text = 'Copied!'
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1500
    $localTimer = $timer
    $timer.Add_Tick({
        $btnCopy.Text = 'Copy Command'
        $localTimer.Stop()
        $localTimer.Dispose()
    }.GetNewClosure())
    $timer.Start()
}.GetNewClosure())
$mainSplit.Panel2.Controls.Add($btnCopy)
$script:btnCopy = $btnCopy

$btnReset = New-Object System.Windows.Forms.Button
$btnReset.Text = 'Reset All Overrides'
$btnReset.Location = [System.Drawing.Point]::new(143, 172)
$btnReset.Size = [System.Drawing.Size]::new(160, 32)
$btnReset.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$btnReset.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnReset.Add_Click({
    foreach ($state in $script:OptionStates) {
        $state.Override.Checked = $false
    }
    & ${function:Refresh-Preview}
}.GetNewClosure())
$mainSplit.Panel2.Controls.Add($btnReset)
$script:btnReset = $btnReset

$btnLaunch = New-Object System.Windows.Forms.Button
$btnLaunch.Text = 'Run llama-server'
$btnLaunch.Location = [System.Drawing.Point]::new(1088, 168)
$btnLaunch.Size = [System.Drawing.Size]::new(240, 36)
$btnLaunch.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$btnLaunch.BackColor = [System.Drawing.Color]::FromArgb(46, 139, 87)
$btnLaunch.ForeColor = [System.Drawing.Color]::White
$btnLaunch.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnLaunch.FlatAppearance.BorderSize = 0
$btnLaunch.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnLaunch.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$mainSplit.Panel2.Controls.Add($btnLaunch)
$script:btnLaunch = $btnLaunch

$txtServer.Add_TextChanged({ & ${function:Refresh-Preview} }.GetNewClosure())
$txtModel.Add_TextChanged({ & ${function:Refresh-Preview} }.GetNewClosure())
$cmbMode.Add_SelectedIndexChanged({
    & ${function:Update-ModeHint}
    & ${function:Update-ViewMode}
}.GetNewClosure())
$cmbView.Add_SelectedIndexChanged({
    & ${function:Update-ModeHint}
    & ${function:Update-ViewMode}
}.GetNewClosure())
$form.Add_Shown({ & ${function:Update-WindowLayout} }.GetNewClosure())
$form.Add_SizeChanged({ & ${function:Update-WindowLayout} }.GetNewClosure())
$mainSplit.Add_SplitterMoved({ & ${function:Update-WindowLayout} }.GetNewClosure())

foreach ($dir in @($script:BatDir, (Get-Location).Path) | Where-Object { $_ } | Select-Object -Unique) {
    $candidate = Join-Path $dir 'llama-server.exe'
    if (Test-Path $candidate) {
        $txtServer.Text = $candidate
        break
    }
}

$btnLaunch.Add_Click({
    if (-not $script:txtServer.Text -or -not (Test-Path $script:txtServer.Text)) {
        [System.Windows.Forms.MessageBox]::Show(
            'Please select a valid llama-server.exe.',
            'Missing Server',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    if ($script:txtModel.Text -and -not (Test-Path $script:txtModel.Text)) {
        [System.Windows.Forms.MessageBox]::Show(
            'The selected local model path does not exist. Clear it if you intend to use an alternative model source instead.',
            'Invalid Model Path',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    if ($script:txtToolWorkingDir.Text -and -not (Test-Path $script:txtToolWorkingDir.Text -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show(
            'The selected tool working folder does not exist or is not a folder.',
            'Invalid Tool Working Folder',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    $mode = [string]$script:cmbMode.SelectedItem
    $hasMainSource = & ${function:Test-MainModelSourcePresent}
    $hasRouterSource = & ${function:Test-RouterSourcePresent}

    if ($mode -eq 'Single Model' -and -not $hasMainSource) {
        [System.Windows.Forms.MessageBox]::Show(
            'Single Model mode needs a local GGUF model or a checked alternative model source such as --hf-repo, --model-url, --docker-repo, or a built-in default profile.',
            'Missing Model Source',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    if ($mode -eq 'Router' -and -not ($hasMainSource -or $hasRouterSource)) {
        [System.Windows.Forms.MessageBox]::Show(
            'Router mode needs a router source such as --models-dir or --models-preset, or another main model source.',
            'Missing Router Source',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:txtServer.Text
    $psi.Arguments = (((& ${function:Get-ArgumentTokens}) | ForEach-Object { & ${function:Quote-WindowsArgument} $_ }) -join ' ')
    if (-not [string]::IsNullOrWhiteSpace($script:txtToolWorkingDir.Text)) {
        $psi.WorkingDirectory = $script:txtToolWorkingDir.Text
    }
    $psi.UseShellExecute = $true
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    $form.Close()
})

Update-ModeHint
Update-ViewMode
[void]$form.ShowDialog()

} catch {
    $logPath = Join-Path $env:TEMP 'llm-launcher-last-error.txt'
    $errorLines = @(
        'Launcher Error'
        ('Message: ' + $_.Exception.Message)
        ('Line: ' + $_.InvocationInfo.ScriptLineNumber)
        ''
        'Script Stack Trace:'
        $_.ScriptStackTrace
    )
    $errorLines | Set-Content -LiteralPath $logPath -Encoding UTF8

    Write-Host ''
    Write-Host 'Launcher Error' -ForegroundColor Red
    Write-Host ('Message: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ('Line: ' + $_.InvocationInfo.ScriptLineNumber) -ForegroundColor Yellow
    if ($_.ScriptStackTrace) {
        Write-Host ''
        Write-Host 'Script Stack Trace:' -ForegroundColor Yellow
        Write-Host $_.ScriptStackTrace
    }
    Write-Host ''
    Write-Host ('Saved copy to: ' + $logPath)
    exit 1
}
