@echo off
setlocal EnableExtensions DisableDelayedExpansion
title llama-server-launcher
echo Starting GUI, please wait...

set "_pwsh=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%_pwsh%" set "_pwsh=powershell.exe"
set "LLM_LAUNCHER_BAT=%~f0"

"%_pwsh%" -NoProfile -STA -Command "$ErrorActionPreference = 'Stop'; $bat = $env:LLM_LAUNCHER_BAT; if ([string]::IsNullOrWhiteSpace($bat)) { throw 'Launcher path missing.' }; $marker = '#' + 'PSSTART'; $content = [System.IO.File]::ReadAllText($bat); $index = $content.LastIndexOf($marker, [System.StringComparison]::Ordinal); if ($index -lt 0) { throw 'Embedded script marker not found.' }; $scriptText = $content.Substring($index + $marker.Length); . ([scriptblock]::Create($scriptText)) -BatPath $bat"
set "_ec=%errorlevel%"
if not "%_ec%"=="0" (
    echo.
    echo [ERROR] The launcher failed. Review the details above and copy them if needed.
    pause
)
endlocal & exit /b %_ec%
#PSSTART
param(
    [string]$BatPath
)

try {
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $eventArgs)

    $logPath = Join-Path $env:TEMP 'llm-launcher-last-error.txt'
    $errorLines = @(
        'Launcher UI Error'
        ('Message: ' + $eventArgs.Exception.Message)
        ''
        'Exception:'
        $eventArgs.Exception.ToString()
    )
    $errorLines | Set-Content -LiteralPath $logPath -Encoding UTF8

    [System.Windows.Forms.MessageBox]::Show(
        ('The launcher hit a UI error and saved details to:' + [Environment]::NewLine + $logPath + [Environment]::NewLine + [Environment]::NewLine + $eventArgs.Exception.Message),
        'Launcher Error',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
})

$script:InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
$script:CpuCores = [Environment]::ProcessorCount
$script:BatDir = if ($BatPath) { Split-Path -Parent $BatPath } else { (Get-Location).Path }
$script:OptionCatalog = [System.Collections.ArrayList]::new()
$script:OptionStates = [System.Collections.ArrayList]::new()
$script:OptionStatesById = @{}
$script:SamplerPresets = [ordered]@{
    'Choose preset...' = $null
    'Thinking - General' = @{
        temp             = 1.00
        top_k            = 20
        top_p            = 0.95
        min_p            = 0.00
        repeat_penalty   = 1.00
    }
    'Thinking - Coding' = @{
        temp             = 0.60
        top_k            = 20
        top_p            = 0.95
        min_p            = 0.00
        repeat_penalty   = 1.00
    }
    'Instruct - Balanced' = @{
        temp             = 0.70
        top_k            = 20
        top_p            = 0.80
        min_p            = 0.00
        repeat_penalty   = 1.00
        presence_penalty = 1.50
    }
}
$script:ApplyingSamplerPreset = $false
$script:TabPages = @{}
$script:TabTitles = @{}
$script:TabLayouts = @{}
$script:AllOptionsPage = $null
$script:AllOptionsSearchLabel = $null
$script:AllOptionsList = $null
$script:AllOptionsSearch = $null
$script:AllOptionsClearButton = $null
$script:AllOptionsFilterPanel = $null
$script:AllOptionsCountLabel = $null
$script:AllOptionsEmptyState = $null
$script:AllOptionsEditorPanel = $null
$script:AllOptionsEditorTitle = $null
$script:AllOptionsEditorMeta = $null
$script:AllOptionsEditorFlag = $null
$script:AllOptionsUseLabel = $null
$script:AllOptionsValueLabel = $null
$script:AllOptionsHelpLabel = $null
$script:AllOptionsEditorEmpty = $null
$script:AllOptionsSelectedState = $null
$script:AllOptionsRefreshing = $false
$script:AllOptionsFilter = 'All'
$script:AllOptionsFilterButtons = $null
$script:SuppressMainTabEvents = $false
$script:LastMainTabKey = ''
$script:txtServer = $null
$script:txtModel = $null
$script:txtPreview = $null
$script:lblModel = $null
$script:form = $null
$script:titleLabel = $null
$script:subtitleLabel = $null
$script:grpRequired = $null
$script:lblServerRequired = $null
$script:btnServer = $null
$script:btnModel = $null
$script:mainSplit = $null
$script:previewLabel = $null
$script:btnCopy = $null
$script:btnReset = $null
$script:btnSaveCmd = $null
$script:btnLaunch = $null
$script:HoverHelpLabel = $null
$script:LayoutInProgress = $false
$script:LayoutRequested = $false
$script:LayoutTimer = $null
$script:LastLayoutWidth = 0

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

function Enable-DoubleBuffer {
    param($Control)

    if (-not $Control) { return }
    try {
        $prop = $Control.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic, Instance')
        if ($prop) { $prop.SetValue($Control, $true, $null) }
    } catch { }
}

function Disable-LabelMnemonics {
    param($Control)

    if (-not $Control) { return }
    if ($Control -is [System.Windows.Forms.Label]) {
        $Control.UseMnemonic = $false
    }
    foreach ($child in $Control.Controls) {
        & ${function:Disable-LabelMnemonics} -Control $child
    }
}

function Get-HoverHelpLabel {
    if (-not $script:form -or $script:form.IsDisposed) { return $null }

    if (-not $script:HoverHelpLabel -or $script:HoverHelpLabel.IsDisposed) {
        $label = New-Object System.Windows.Forms.Label
        $label.Visible = $false
        $label.AutoSize = $false
        $label.UseMnemonic = $false
        $label.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
        $label.BackColor = [System.Drawing.SystemColors]::Info
        $label.ForeColor = [System.Drawing.SystemColors]::InfoText
        $label.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $label.Padding = [System.Windows.Forms.Padding]::new(8)
        $script:form.Controls.Add($label)
        $script:HoverHelpLabel = $label
    }
    return $script:HoverHelpLabel
}

function Hide-HoverHelp {
    if ($script:HoverHelpLabel -and -not $script:HoverHelpLabel.IsDisposed) {
        $script:HoverHelpLabel.Visible = $false
    }
}

function Show-HoverHelp {
    param(
        $Control,
        [string]$Text
    )

    if (-not $Control -or $Control.IsDisposed -or [string]::IsNullOrWhiteSpace($Text)) { return }

    $label = & ${function:Get-HoverHelpLabel}
    if (-not $label) { return }

    $maxWidth = [Math]::Min(520, [Math]::Max(300, ($script:form.ClientSize.Width - 40)))
    $measureSize = [System.Drawing.Size]::new(($maxWidth - 20), 1000)
    $flags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
    $textSize = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $label.Font, $measureSize, $flags)
    $width = [Math]::Min($maxWidth, [Math]::Max(260, ($textSize.Width + 22)))
    $height = [Math]::Min(220, [Math]::Max(42, ($textSize.Height + 18)))

    $point = $script:form.PointToClient($Control.PointToScreen([System.Drawing.Point]::new(0, ($Control.Height + 4))))
    if (($point.X + $width) -gt ($script:form.ClientSize.Width - 8)) {
        $point.X = [Math]::Max(8, ($script:form.ClientSize.Width - $width - 8))
    }
    if (($point.Y + $height) -gt ($script:form.ClientSize.Height - 8)) {
        $point = $script:form.PointToClient($Control.PointToScreen([System.Drawing.Point]::new(0, (-1 * $height - 4))))
        if ($point.Y -lt 8) { $point.Y = 8 }
    }

    $label.Text = $Text
    $label.Location = $point
    $label.Size = [System.Drawing.Size]::new($width, $height)
    $label.Visible = $true
    $label.BringToFront()
}

function Register-HelpText {
    param(
        $Control,
        [string]$Title,
        [string]$Text
    )

    if (-not $Control -or [string]::IsNullOrWhiteSpace($Text)) { return }

    $message = if ([string]::IsNullOrWhiteSpace($Title)) {
        $Text
    } else {
        $Title + "`r`n" + $Text
    }

    $localControl = $Control
    $localMessage = $message
    $Control.Add_MouseEnter({
        & ${function:Show-HoverHelp} -Control $localControl -Text $localMessage
    }.GetNewClosure())
    $Control.Add_MouseLeave({ & ${function:Hide-HoverHelp} }.GetNewClosure())
    $Control.Add_MouseDown({ & ${function:Hide-HoverHelp} }.GetNewClosure())
}

function Register-OptionHelp {
    param(
        [Parameter(Mandatory = $true)]
        $State
    )

    & ${function:Register-HelpText} -Control $State.Label -Title $State.Meta.Label -Text $State.Meta.Tooltip
}

$script:TooltipHints = @{
    api_key                  = 'Authentication key accepted by the server. Strongly recommended for network access.'
    api_key_file             = 'File containing API keys accepted by the server.'
    chat_template            = 'Template used to turn chat messages into the model prompt.'
    chat_template_file       = 'Custom Jinja chat template file.'
    chat_template_kwargs     = 'Advanced JSON forwarded to the chat template parser.'
    default_profile          = 'Built-in download/profile shortcut documented by llama-server.'
    direct_io                = 'Uses Direct I/O if available. Leave disabled unless you know your storage path benefits from it.'
    fit                      = 'Lets llama-server adjust unset memory options to fit available device memory.'
    hf_repo                  = 'Loads a model from Hugging Face instead of a local GGUF file.'
    hf_file                  = 'Selects an exact file inside the Hugging Face repo.'
    jinja                    = 'Uses the Jinja template engine for chat templates.'
    media_path               = 'Folder used to resolve local media files in requests.'
    mlock                    = 'Keeps the model in RAM to reduce swapping. Can starve other applications on memory-limited systems.'
    models_dir               = 'Router mode folder containing local model files.'
    models_preset            = 'Router mode INI file containing named model presets.'
    no_host                  = 'Bypasses the host buffer so extra buffers can be used.'
    numa                     = 'NUMA placement strategy. Useful mainly on multi-socket or workstation/server systems.'
    reasoning                = 'Server-level reasoning/thinking mode.'
    reasoning_budget         = 'Token budget for model thinking.'
    reasoning_format         = 'Controls how thinking blocks are parsed into API response fields.'
    tools                    = 'Experimental built-in tools for the Web UI. Use only with trusted folders.'
    tool_working_dir         = 'Working directory used by built-in tools.'
    utility_action           = 'One-shot command such as help, version, cache list, or list devices. Clear the model field and uncheck other rows for a pure utility command.'
    webui_mcp_proxy          = 'Experimental MCP CORS proxy. Do not enable in untrusted environments.'
}

$script:BasicTooltipHints = @{
    host                    = 'The address llama-server listens on. 127.0.0.1 means only this PC can connect. Use 0.0.0.0 only when you intentionally want other devices on your network to reach the server, and protect it with an API key.'
    port                    = 'The HTTP port for the API and Web UI. The upstream default is 8080. Change it only if another program already uses that port or you want a separate server on a separate port.'
    api_key                 = 'Adds API authentication. Use this before exposing the server beyond 127.0.0.1. You can enter one key or multiple comma-separated keys, depending on how you want clients to authenticate.'
    hf_repo                 = 'Downloads or loads a model from Hugging Face instead of using a local GGUF file. Format is usually owner/model, optionally with :quant. Current llama-server defaults to Q4_K_M when possible, or falls back to an available file.'
    hf_file                 = 'Chooses the exact file inside the Hugging Face repo. Use this when the repo contains several quantizations or split files and you do not want llama-server to guess.'
    sampler_preset          = 'A launcher-side shortcut for common sampling styles. Pick a preset, click Apply, then fine tune the visible sampler values. It does not add a hidden preset flag.'
    temp                    = 'Temperature controls randomness. Lower values are steadier and more repeatable. Higher values are more varied and creative. Current upstream default is 0.80.'
    top_k                   = 'Limits token choice to the K most likely next tokens. Current upstream default is 40. A smaller value is more conservative. 0 disables this sampler.'
    top_p                   = 'Nucleus sampling keeps the smallest set of likely tokens whose total probability reaches P. Current upstream default is 0.95. Lower values narrow the output.'
    min_p                   = 'Filters out tokens whose probability is too small compared with the most likely token. Current upstream default is 0.05. 0 disables this sampler.'
    repeat_penalty          = 'Penalizes tokens that appeared recently so the model is less likely to loop or repeat phrases. Current upstream default is 1.00, which means disabled.'
    presence_penalty        = 'Penalizes tokens that have appeared anywhere in the recent context, encouraging the model to introduce new topics. Current upstream default is 0.00.'
    seed                    = 'Random seed for generation. -1 picks a random seed each run. Set a fixed number when you want more repeatable output with the same model and settings.'
    reasoning               = 'Controls model thinking mode at the server/template level. auto lets llama-server detect what the template supports. on or off force the behavior when a model card says to do so.'
    reasoning_budget        = 'Maximum thinking tokens. -1 is unrestricted. 0 tries to end thinking immediately. A positive number gives thinking a fixed budget before the answer continues.'
    enable_thinking         = 'Sets chat_template_kwargs.enable_thinking without hand-writing JSON. Use it for templates that expose an enable_thinking switch, especially Qwen-style thinking models.'
    preserve_thinking       = 'Sets chat_template_kwargs.preserve_thinking without hand-writing JSON. It controls whether supported templates keep prior reasoning content in the conversation history.'
    chat_template           = 'Selects a built-in chat template. Usually leave this unchecked so llama-server uses the template stored in the model metadata. Override only when the model card or your testing says the automatic choice is wrong.'
    jinja                   = 'Enables the Jinja chat template engine. Current llama-server default is enabled. Most modern chat templates expect it, so leave this alone unless you are debugging a template problem.'
    n_gpu_layers            = 'How much of the model to place in VRAM. auto lets llama-server decide. 0 forces CPU-only. all tries to place every layer on GPU. More GPU layers are usually faster but need more VRAM.'
    fit                     = 'Lets llama-server adjust unset arguments to fit device memory. Current upstream default is on. It is a good beginner setting because it reduces out-of-memory starts.'
    ctx_size                = 'Context window size: how much text the model can consider. 0 means use the model default. Larger context uses more RAM or VRAM, especially with multiple slots.'
    batch_size              = 'Logical maximum batch size for prompt processing. Current upstream default is 2048. Larger can improve throughput but may use more memory.'
    flash_attn              = 'Flash Attention can reduce memory use and speed up supported models and hardware. auto is the safest choice because llama-server decides whether it is supported.'
    cache_type_v            = 'KV cache value precision. Current upstream default is f16. Lower precision can save memory, but f16 is the conservative compatibility choice.'
    threads                 = 'CPU generation threads. -1 lets llama-server choose automatically. Set a number when you want to limit CPU use or tune CPU-only performance.'
    mmproj                  = 'Path to the multimodal projector file used by some vision models. If you load from Hugging Face, llama-server can often download the projector automatically when available.'
    tools                   = 'Enables experimental built-in tools for the Web UI. all enables every tool; a comma-separated list enables specific tools such as read_file, grep_search, exec_shell_command, write_file, edit_file, apply_diff, and get_datetime. Use only in trusted folders.'
    tool_working_dir        = 'The folder where built-in tools run. This is a launcher setting for process working directory. Pick a trusted project folder because write and shell tools can modify files.'
    models_dir              = 'Router mode model folder. In router mode, llama-server can load and unload models dynamically from this folder instead of starting with one fixed model.'
    models_preset           = 'Router mode preset INI file. Each section defines a named model preset; command-line options override preset values, and model-specific preset values override global preset values.'
    models_max              = 'Router mode limit for how many models can be loaded at once. Current upstream default is 4. 0 means unlimited, which can consume a lot of memory.'
    models_autoload         = 'Router mode automatic loading. Current upstream default is enabled. Disable it when you want the router to expose presets without loading models until requested.'
}

function New-OptionTooltip {
    param(
        [string]$Id,
        [string]$Label,
        [string]$Type,
        [string]$DisplayFlag,
        $Default,
        $Choices,
        [bool]$Basic,
        [string]$Kind
    )

    $parts = New-Object System.Collections.Generic.List[string]

    if ($Basic -and $script:BasicTooltipHints.ContainsKey($Id)) {
        [void]$parts.Add($script:BasicTooltipHints[$Id])
    } elseif ($script:TooltipHints.ContainsKey($Id)) {
        [void]$parts.Add($script:TooltipHints[$Id])
    } else {
        [void]$parts.Add(($Label + ' setting.'))
    }

    if (-not [string]::IsNullOrWhiteSpace($DisplayFlag)) {
        if ($Kind -eq 'CLI') {
            [void]$parts.Add(('Flag: ' + $DisplayFlag))
        } else {
            [void]$parts.Add(('Command effect: ' + $DisplayFlag))
        }
    }

    if ($Default -ne $null -and $Type -notin @('flag', 'flagchoice', 'preset')) {
        [void]$parts.Add(('Default: ' + [string]$Default))
    }

    if ($Choices -and $Choices.Count -gt 0 -and $Type -ne 'flagchoice') {
        $choiceText = (($Choices | ForEach-Object { [string]$_ }) -join ', ')
        if ($choiceText.Length -le 160) {
            [void]$parts.Add(('Choices: ' + $choiceText))
        }
    }

    if ($Basic) {
        [void]$parts.Add('Shown in Quick Setup.')
    }

    return ($parts -join "`n")
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
        [string]$DisplayFlag = '',
        [string]$Kind = '',
        [int]$Arity = 1
    )

    if ([string]::IsNullOrWhiteSpace($Kind)) {
        if ($Type -eq 'preset' -or ([string]::IsNullOrWhiteSpace($Flag) -and $Type -ne 'flagchoice')) {
            $Kind = 'Launcher'
        } else {
            $Kind = 'CLI'
        }
    }

    if (-not $DisplayFlag) {
        if ($Type -eq 'pair' -and $NegFlag) {
            $DisplayFlag = "$Flag / $NegFlag"
        } elseif ($Type -eq 'flagchoice' -and $Choices) {
            $DisplayFlag = (($Choices | ForEach-Object { $_.Flag }) -join ', ')
        } else {
            $DisplayFlag = $Flag
        }
    }

    if ([string]::IsNullOrWhiteSpace($Tooltip)) {
        $Tooltip = New-OptionTooltip -Id $Id -Label $Label -Type $Type -DisplayFlag $DisplayFlag -Default $Default -Choices $Choices -Basic $Basic -Kind $Kind
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
        Kind        = $Kind
        Arity       = $Arity
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
    if ($Value -notmatch '[\s"&|<>^()]') { return $Value }

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

function Quote-CmdArgument {
    param(
        [AllowNull()]
        [string]$Value
    )

    $quoted = Quote-WindowsArgument -Value $Value
    if (-not $quoted.StartsWith('"')) {
        $quoted = '"' + $quoted + '"'
    }
    return $quoted -replace '%', '%%'
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
        try {
            $dialog.Description = $Title
            if ($StartDir -and (Test-Path -LiteralPath $StartDir)) {
                $dialog.SelectedPath = $StartDir
            }
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                return $dialog.SelectedPath
            }
            return $null
        } finally {
            $dialog.Dispose()
        }
    }

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $dialog.Title = $Title
        $dialog.Filter = $Filter
        if ($StartDir -and (Test-Path -LiteralPath $StartDir)) {
            $dialog.InitialDirectory = $StartDir
        }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }
        return $null
    } finally {
        $dialog.Dispose()
    }
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
        'preset' {
            return [string]$State.Control.SelectedItem
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

function Test-OptionEffectActive {
    param(
        [Parameter(Mandatory = $true)]
        $State
    )

    if ($State.Meta.Type -eq 'preset') {
        return $false
    }

    return [bool]$State.Override.Checked
}

function Should-IncludeModelPath {
    if (-not $script:txtModel) { return $false }
    if ([string]::IsNullOrWhiteSpace($script:txtModel.Text)) { return $false }
    return $true
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

    if ([string]::IsNullOrEmpty($meta.Flag) -and $meta.Type -ne 'flagchoice') {
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
            $rawText = [string]$State.Control.Text
            if (-not [string]::IsNullOrWhiteSpace($rawText)) {
                [void]$tokens.Add($meta.Flag)
                $arity = if ($meta.Arity) { [int]$meta.Arity } else { 1 }
                if ($arity -gt 1) {
                    $parts = $rawText.Trim() -split '\s+'
                    foreach ($part in $parts) {
                        if (-not [string]::IsNullOrEmpty($part)) {
                            [void]$tokens.Add($part)
                        }
                    }
                } else {
                    [void]$tokens.Add($rawText)
                }
            }
        }
    }

    return $tokens
}

function Get-ArgumentTokens {
    $tokens = New-Object System.Collections.Generic.List[string]

    if (& ${function:Should-IncludeModelPath}) {
        [void]$tokens.Add('--model')
        [void]$tokens.Add($script:txtModel.Text)
    }

    $kwargIds = @('enable_thinking', 'preserve_thinking', 'chat_template_kwargs')

    foreach ($state in $script:OptionStates) {
        if ($kwargIds -contains $state.Meta.Id) { continue }
        $stateTokens = Get-OptionTokens -State $state
        foreach ($token in $stateTokens) {
            [void]$tokens.Add($token)
        }
    }

    $kwargs = [ordered]@{}

    $thinkingState = Get-OptionStateById -Id 'enable_thinking'
    if ($thinkingState -and $thinkingState.Override.Checked) {
        $sel = [string]$thinkingState.Control.SelectedItem
        if ($sel -eq 'Force on') { $kwargs['enable_thinking'] = $true }
        elseif ($sel -eq 'Force off') { $kwargs['enable_thinking'] = $false }
    }

    $preserveState = Get-OptionStateById -Id 'preserve_thinking'
    if ($preserveState -and $preserveState.Override.Checked) {
        $sel = [string]$preserveState.Control.SelectedItem
        if ($sel -eq 'Enabled') { $kwargs['preserve_thinking'] = $true }
        elseif ($sel -eq 'Disabled') { $kwargs['preserve_thinking'] = $false }
    }

    $rawState = Get-OptionStateById -Id 'chat_template_kwargs'
    $rawText = ''
    if ($rawState -and $rawState.Override.Checked) {
        $rawText = [string]$rawState.Control.Text
    }

    if (-not [string]::IsNullOrWhiteSpace($rawText)) {
        $rawParsed = $null
        try {
            $rawParsed = ConvertFrom-Json -InputObject $rawText -ErrorAction Stop
        } catch {
            $rawParsed = $null
        }

        $isJsonObject = ($null -ne $rawParsed) -and ($rawParsed.GetType().FullName -eq 'System.Management.Automation.PSCustomObject')
        if ($isJsonObject) {
            foreach ($prop in $rawParsed.PSObject.Properties) {
                $kwargs[$prop.Name] = $prop.Value
            }
            if ($kwargs.Count -gt 0) {
                [void]$tokens.Add('--chat-template-kwargs')
                [void]$tokens.Add((ConvertTo-Json -InputObject $kwargs -Compress -Depth 32))
            }
        } else {
            [void]$tokens.Add('--chat-template-kwargs')
            [void]$tokens.Add($rawText)
        }
    } elseif ($kwargs.Count -gt 0) {
        [void]$tokens.Add('--chat-template-kwargs')
        [void]$tokens.Add((ConvertTo-Json -InputObject $kwargs -Compress -Depth 32))
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

function Get-IsAllOptionsSelected {
    return ($script:MainTabs -and $script:MainTabs.SelectedTab -and [string]$script:MainTabs.SelectedTab.Tag -eq 'AllOptions')
}

function Get-AllOptionsSearchText {
    param(
        [Parameter(Mandatory = $true)]
        $State
    )

    return (@(
        $State.Meta.Label
        $State.Meta.DisplayFlag
        $State.Meta.Tab
        $State.Meta.Section
        $State.Meta.Kind
        $State.Meta.Tooltip
    ) -join ' ')
}

function Get-AllOptionsRows {
    $query = if ($script:AllOptionsSearch) { $script:AllOptionsSearch.Text.Trim() } else { '' }
    $filter = if ($script:AllOptionsFilter) { [string]$script:AllOptionsFilter } else { 'All' }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($state in $script:OptionStates) {
        if ($filter -eq 'Basic' -and -not $state.Meta.Basic) { continue }
        if ($filter -eq 'Active' -and -not (& ${function:Test-OptionEffectActive} -State $state)) { continue }

        $searchText = & ${function:Get-AllOptionsSearchText} -State $state
        if ($query -and $searchText.IndexOf($query, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            continue
        }

        [void]$rows.Add($state)
    }

    return $rows
}

function Set-AllOptionsListItemStyle {
    param(
        [Parameter(Mandatory = $true)] $Item,
        [Parameter(Mandatory = $true)] $State
    )

    $active = & ${function:Test-OptionEffectActive} -State $State
    $Item.Text = if ($active) { [string][char]0x25CF } else { '' }

    if ($active) {
        $Item.BackColor = [System.Drawing.Color]::FromArgb(232, 245, 233)
        $Item.ForeColor = [System.Drawing.Color]::FromArgb(20, 90, 50)
    } else {
        $Item.BackColor = [System.Drawing.SystemColors]::Window
        $Item.ForeColor = [System.Drawing.SystemColors]::WindowText
    }
    $Item.UseItemStyleForSubItems = $true
}

function Update-AllOptionsFilterButtons {
    if (-not $script:AllOptionsFilterButtons) { return }

    foreach ($btn in $script:AllOptionsFilterButtons) {
        if ($btn.Tag -eq $script:AllOptionsFilter) {
            $btn.BackColor = [System.Drawing.Color]::FromArgb(46, 139, 87)
            $btn.ForeColor = [System.Drawing.Color]::White
            $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(46, 139, 87)
        } else {
            $btn.BackColor = [System.Drawing.Color]::White
            $btn.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
            $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(190, 190, 190)
        }
    }
}

function Set-AllOptionsFilter {
    param([string]$Filter)

    if ($Filter -ne 'Active' -and $Filter -ne 'Basic') {
        $Filter = 'All'
    }

    $script:AllOptionsFilter = $Filter
    & ${function:Refresh-AllOptionsList}

    if ($script:AllOptionsSearch) {
        [void]$script:AllOptionsSearch.Focus()
    }
}

function Update-AllOptionsListColumns {
    if (-not $script:AllOptionsList -or $script:AllOptionsList.Columns.Count -lt 3) { return }

    $clientWidth = [Math]::Max(280, $script:AllOptionsList.ClientSize.Width)
    $activeWidth = 24
    $settingWidth = [Math]::Max(150, [Math]::Min(250, [int]($clientWidth * 0.42)))
    $effectWidth = [Math]::Max(160, ($clientWidth - $activeWidth - $settingWidth - 4))

    $script:AllOptionsList.Columns[0].Width = $activeWidth
    $script:AllOptionsList.Columns[1].Width = $settingWidth
    $script:AllOptionsList.Columns[2].Width = $effectWidth
}

function Update-AllOptionsPageLayout {
    $page = $script:AllOptionsPage
    if (-not $page) { return }

    $page.SuspendLayout()
    try {
        $pageWidth = [Math]::Max(720, $page.ClientSize.Width)
        $pageHeight = [Math]::Max(260, $page.ClientSize.Height)
        $margin = 12
        $gap = 8
        $wideToolbar = ($pageWidth -ge 920)

        if ($script:AllOptionsSearchLabel) {
            $script:AllOptionsSearchLabel.Location = [System.Drawing.Point]::new($margin, 10)
            $script:AllOptionsSearchLabel.Size = [System.Drawing.Size]::new([Math]::Max(260, ($pageWidth - ($margin * 2))), 18)
        }

        $toolbarY = 32
        $listTop = 70
        $clearWidth = 58
        $countWidth = if ($wideToolbar) { 190 } else { 170 }
        $filterWidth = 330

        if ($wideToolbar) {
            $countX = [Math]::Max($margin, ($pageWidth - $margin - $countWidth))
            $filterX = [Math]::Max($margin, ($countX - $filterWidth - 14))
            $searchWidth = [Math]::Max(240, ($filterX - $margin - $clearWidth - $gap - 14))

            if ($script:AllOptionsSearch) {
                $script:AllOptionsSearch.Location = [System.Drawing.Point]::new($margin, $toolbarY)
                $script:AllOptionsSearch.Size = [System.Drawing.Size]::new($searchWidth, 26)
            }
            if ($script:AllOptionsClearButton) {
                $script:AllOptionsClearButton.Location = [System.Drawing.Point]::new(($margin + $searchWidth + $gap), $toolbarY)
            }
            if ($script:AllOptionsFilterPanel) {
                $script:AllOptionsFilterPanel.Location = [System.Drawing.Point]::new($filterX, 30)
                $script:AllOptionsFilterPanel.Size = [System.Drawing.Size]::new($filterWidth, 30)
            }
            if ($script:AllOptionsCountLabel) {
                $script:AllOptionsCountLabel.Location = [System.Drawing.Point]::new($countX, 36)
                $script:AllOptionsCountLabel.Size = [System.Drawing.Size]::new($countWidth, 20)
            }
        } else {
            $searchWidth = [Math]::Max(220, ($pageWidth - ($margin * 2) - $clearWidth - $gap))
            if ($script:AllOptionsSearch) {
                $script:AllOptionsSearch.Location = [System.Drawing.Point]::new($margin, $toolbarY)
                $script:AllOptionsSearch.Size = [System.Drawing.Size]::new($searchWidth, 26)
            }
            if ($script:AllOptionsClearButton) {
                $script:AllOptionsClearButton.Location = [System.Drawing.Point]::new(($margin + $searchWidth + $gap), $toolbarY)
            }
            if ($script:AllOptionsFilterPanel) {
                $script:AllOptionsFilterPanel.Location = [System.Drawing.Point]::new($margin, 62)
                $script:AllOptionsFilterPanel.Size = [System.Drawing.Size]::new($filterWidth, 30)
            }
            if ($script:AllOptionsCountLabel) {
                $script:AllOptionsCountLabel.Location = [System.Drawing.Point]::new([Math]::Max($margin, ($pageWidth - $margin - $countWidth)), 68)
                $script:AllOptionsCountLabel.Size = [System.Drawing.Size]::new($countWidth, 20)
            }
            $listTop = 102
        }

        $bodyHeight = [Math]::Max(180, ($pageHeight - $listTop - $margin))
        $bodyWidth = [Math]::Max(300, ($pageWidth - ($margin * 2)))
        $paneGap = 16
        $listWidth = [Math]::Max(340, [Math]::Min(560, [int]($bodyWidth * 0.43)))
        $editorWidth = $bodyWidth - $listWidth - $paneGap

        if ($editorWidth -lt 360) {
            $editorWidth = 360
            $listWidth = [Math]::Max(300, ($bodyWidth - $editorWidth - $paneGap))
        }

        if ($script:AllOptionsList) {
            $script:AllOptionsList.Location = [System.Drawing.Point]::new($margin, $listTop)
            $script:AllOptionsList.Size = [System.Drawing.Size]::new($listWidth, $bodyHeight)
            & ${function:Update-AllOptionsListColumns}
        }

        if ($script:AllOptionsEmptyState) {
            $script:AllOptionsEmptyState.Location = [System.Drawing.Point]::new(($margin + 12), ($listTop + 40))
            $script:AllOptionsEmptyState.Size = [System.Drawing.Size]::new([Math]::Max(180, ($listWidth - 24)), 48)
        }

        if ($script:AllOptionsEditorPanel) {
            $editorX = $margin + $listWidth + $paneGap
            $script:AllOptionsEditorPanel.Location = [System.Drawing.Point]::new($editorX, $listTop)
            $script:AllOptionsEditorPanel.Size = [System.Drawing.Size]::new([Math]::Max(360, $editorWidth), $bodyHeight)
        }
    } finally {
        $page.ResumeLayout($false)
    }

    & ${function:Update-AllOptionsEditorLayout}
}

function Restore-AllOptionsEditorSelection {
    $state = $script:AllOptionsSelectedState
    if (-not $state) { return }

    $targetPage = $state.Page
    if ($targetPage) {
        if ($state.Override -and $state.Override.Parent -ne $targetPage)         { [void]$targetPage.Controls.Add($state.Override) }
        if ($state.Control -and $state.Control.Parent -ne $targetPage)           { [void]$targetPage.Controls.Add($state.Control) }
        if ($state.BrowseButton -and $state.BrowseButton.Parent -ne $targetPage) { [void]$targetPage.Controls.Add($state.BrowseButton) }
    }

    if ($state.Override) { $state.Override.Visible = $false }
    if ($state.Control) { $state.Control.Visible = $false }
    if ($state.BrowseButton) { $state.BrowseButton.Visible = $false }

    $script:AllOptionsSelectedState = $null
}

function Clear-AllOptionsEditor {
    & ${function:Restore-AllOptionsEditorSelection}

    foreach ($ctrl in @(
        $script:AllOptionsEditorTitle,
        $script:AllOptionsEditorMeta,
        $script:AllOptionsEditorFlag,
        $script:AllOptionsUseLabel,
        $script:AllOptionsValueLabel,
        $script:AllOptionsHelpLabel
    )) {
        if ($ctrl) { $ctrl.Visible = $false }
    }

    if ($script:AllOptionsEditorEmpty) {
        $script:AllOptionsEditorEmpty.Visible = $true
        $script:AllOptionsEditorEmpty.Text = 'Select an option to edit.'
    }
}

function Get-AllOptionsEditorControlWidth {
    param(
        [Parameter(Mandatory = $true)]
        $State
    )

    $panelWidth = if ($script:AllOptionsEditorPanel) { $script:AllOptionsEditorPanel.ClientSize.Width } else { 520 }
    $available = [Math]::Max(220, ($panelWidth - 36))
    switch ($State.Meta.Type) {
        'number'     { return [Math]::Min($available, 150) }
        'decimal'    { return [Math]::Min($available, 150) }
        'pair'       { return [Math]::Min($available, 150) }
        'preset'     { return [Math]::Min(($available - 84), 360) }
        'flagchoice' { return [Math]::Min($available, 520) }
        'combo'      { return [Math]::Min($available, 360) }
        'path'       { return [Math]::Max(220, ($available - 84)) }
        'folder'     { return [Math]::Max(220, ($available - 84)) }
        default      { return [Math]::Min($available, 520) }
    }
}

function Update-AllOptionsEditorLayout {
    $state = $script:AllOptionsSelectedState
    $panel = $script:AllOptionsEditorPanel
    if (-not $panel) { return }

    $panelWidth = [Math]::Max(360, $panel.ClientSize.Width)
    $contentWidth = [Math]::Max(260, ($panelWidth - 32))

    if (-not $state) {
        $panel.AutoScrollMinSize = [System.Drawing.Size]::new(0, 0)
        if ($script:AllOptionsEditorEmpty) {
            $script:AllOptionsEditorEmpty.Location = [System.Drawing.Point]::new(16, 14)
            $script:AllOptionsEditorEmpty.Size = [System.Drawing.Size]::new($contentWidth, 28)
        }
        return
    }

    if ($script:AllOptionsEditorTitle) {
        $script:AllOptionsEditorTitle.Location = [System.Drawing.Point]::new(16, 14)
        $script:AllOptionsEditorTitle.Size = [System.Drawing.Size]::new($contentWidth, 24)
    }
    if ($script:AllOptionsEditorMeta) {
        $script:AllOptionsEditorMeta.Location = [System.Drawing.Point]::new(16, 42)
        $script:AllOptionsEditorMeta.Size = [System.Drawing.Size]::new($contentWidth, 20)
    }
    if ($script:AllOptionsEditorFlag) {
        $script:AllOptionsEditorFlag.Location = [System.Drawing.Point]::new(16, 68)
        $script:AllOptionsEditorFlag.Size = [System.Drawing.Size]::new($contentWidth, 20)
    }

    $useY = 104
    $valueY = if ($state.Meta.Type -eq 'preset') { 124 } else { 160 }
    $helpY = if ($state.Meta.Type -eq 'preset') { 166 } else { 202 }

    if ($state.Meta.Type -ne 'preset') {
        if ($state.Override) {
            if ($state.Override.Parent -ne $panel) { [void]$panel.Controls.Add($state.Override) }
            $state.Override.Location = [System.Drawing.Point]::new(16, $useY)
            $state.Override.Size = [System.Drawing.Size]::new(18, 20)
            $state.Override.Visible = $true
        }
        if ($script:AllOptionsUseLabel) {
            $script:AllOptionsUseLabel.Location = [System.Drawing.Point]::new(42, ($useY + 1))
            $script:AllOptionsUseLabel.Size = [System.Drawing.Size]::new([Math]::Max(160, ($contentWidth - 26)), 20)
            $script:AllOptionsUseLabel.Visible = $true
        }
    } else {
        if ($state.Override) { $state.Override.Visible = $false }
        if ($script:AllOptionsUseLabel) { $script:AllOptionsUseLabel.Visible = $false }
    }

    if ($state.Control) {
        if ($script:AllOptionsValueLabel) {
            $script:AllOptionsValueLabel.Text = if ($state.Meta.Type -eq 'preset') { 'Preset' } else { 'Value' }
            $script:AllOptionsValueLabel.Location = [System.Drawing.Point]::new(16, ($valueY - 23))
            $script:AllOptionsValueLabel.Size = [System.Drawing.Size]::new($contentWidth, 18)
            $script:AllOptionsValueLabel.Visible = $true
        }

        if ($state.Control.Parent -ne $panel) { [void]$panel.Controls.Add($state.Control) }
        $controlWidth = & ${function:Get-AllOptionsEditorControlWidth} -State $state
        $state.Control.Location = [System.Drawing.Point]::new(16, $valueY)
        $state.Control.Size = [System.Drawing.Size]::new($controlWidth, $state.Control.Height)
        $state.Control.Visible = $true

        if ($state.Control -is [System.Windows.Forms.ComboBox]) {
            $state.Control.DropDownWidth = [Math]::Max($controlWidth, [Math]::Min(560, $contentWidth))
        }

        if ($state.BrowseButton) {
            if ($state.BrowseButton.Parent -ne $panel) { [void]$panel.Controls.Add($state.BrowseButton) }
            $state.BrowseButton.Location = [System.Drawing.Point]::new(($state.Control.Right + 8), $valueY)
            $state.BrowseButton.Visible = $true
        }
        $helpY = $valueY + 42
    } else {
        if ($script:AllOptionsValueLabel) { $script:AllOptionsValueLabel.Visible = $false }
        if ($state.BrowseButton) { $state.BrowseButton.Visible = $false }
    }

    if ($script:AllOptionsHelpLabel) {
        $helpHeight = [Math]::Max(80, ($panel.ClientSize.Height - $helpY - 16))
        $script:AllOptionsHelpLabel.Location = [System.Drawing.Point]::new(16, $helpY)
        $script:AllOptionsHelpLabel.Size = [System.Drawing.Size]::new($contentWidth, $helpHeight)
        $script:AllOptionsHelpLabel.Visible = $true
        $panel.AutoScrollMinSize = [System.Drawing.Size]::new(0, ($helpY + $helpHeight + 16))
    }
}

function Show-AllOptionsEditor {
    param(
        [Parameter(Mandatory = $true)]
        $State
    )

    if (-not $script:AllOptionsEditorPanel) { return }

    if ($script:AllOptionsSelectedState -and $script:AllOptionsSelectedState.Meta.Id -ne $State.Meta.Id) {
        & ${function:Restore-AllOptionsEditorSelection}
    }

    $script:AllOptionsSelectedState = $State
    if (& ${function:Get-IsAllOptionsSelected}) {
        $script:LastMainTabKey = 'AllOptions'
    }
    $script:AllOptionsEditorPanel.AutoScrollPosition = [System.Drawing.Point]::new(0, 0)
    if ($script:AllOptionsEditorEmpty) { $script:AllOptionsEditorEmpty.Visible = $false }

    if ($script:AllOptionsEditorTitle) {
        $script:AllOptionsEditorTitle.Text = $State.Meta.Label
        $script:AllOptionsEditorTitle.Visible = $true
    }
    if ($script:AllOptionsEditorMeta) {
        $script:AllOptionsEditorMeta.Text = ((Get-TabDisplayTitle $State.Meta.Tab) + ' / ' + $State.Meta.Section)
        $script:AllOptionsEditorMeta.Visible = $true
    }
    if ($script:AllOptionsEditorFlag) {
        $script:AllOptionsEditorFlag.Text = if ($State.Meta.DisplayFlag) { $State.Meta.DisplayFlag } else { 'Launcher setting' }
        $script:AllOptionsEditorFlag.Visible = $true
    }
    if ($script:AllOptionsHelpLabel) {
        $script:AllOptionsHelpLabel.Text = $State.Meta.Tooltip
        $script:AllOptionsHelpLabel.Visible = $true
    }

    & ${function:Update-AllOptionsEditorLayout}
}

function Toggle-AllOptionsSelectedUse {
    $state = $script:AllOptionsSelectedState
    if (-not $state -or -not $state.Override -or $state.Meta.Type -eq 'preset') { return }

    $state.Override.Checked = -not $state.Override.Checked
}

function Update-AllOptionsListItemForState {
    param(
        [Parameter(Mandatory = $true)]
        $State
    )

    if (-not $script:AllOptionsList) { return }
    foreach ($item in $script:AllOptionsList.Items) {
        if ($item.Tag -and $item.Tag.Meta.Id -eq $State.Meta.Id) {
            & ${function:Set-AllOptionsListItemStyle} -Item $item -State $State
            break
        }
    }
}

function Refresh-AllOptionsList {
    if (-not $script:AllOptionsList) { return }

    & ${function:Update-AllOptionsFilterButtons}

    $rows = @(& ${function:Get-AllOptionsRows})
    $total = $script:OptionStates.Count
    $selectedStillVisible = $false
    $script:AllOptionsRefreshing = $true
    try {
        $script:AllOptionsList.Items.Clear()

        foreach ($state in $rows) {
            try {
                $item = New-Object System.Windows.Forms.ListViewItem('')
                [void]$item.SubItems.Add($state.Meta.Label)
                [void]$item.SubItems.Add($state.Meta.DisplayFlag)
                $item.Tag = $state
                & ${function:Set-AllOptionsListItemStyle} -Item $item -State $state
                [void]$script:AllOptionsList.Items.Add($item)

                if ($script:AllOptionsSelectedState -and $script:AllOptionsSelectedState.Meta.Id -eq $state.Meta.Id) {
                    $selectedStillVisible = $true
                }
            } catch {
                throw ('Could not add All Options row for ' + $state.Meta.Id + ': ' + $_.Exception.Message)
            }
        }
    } finally {
        $script:AllOptionsRefreshing = $false
    }

    if ((& ${function:Get-IsAllOptionsSelected}) -and $script:AllOptionsSelectedState -and -not $selectedStillVisible) {
        & ${function:Clear-AllOptionsEditor}
    } elseif ((& ${function:Get-IsAllOptionsSelected}) -and -not $script:AllOptionsSelectedState -and $rows.Count -eq 0) {
        & ${function:Clear-AllOptionsEditor}
    }

    $shown = $rows.Count
    if ($script:AllOptionsCountLabel) {
        $query = if ($script:AllOptionsSearch) { $script:AllOptionsSearch.Text.Trim() } else { '' }
        $filter = if ($script:AllOptionsFilter) { [string]$script:AllOptionsFilter } else { 'All' }
        if ($shown -eq $total -and $filter -eq 'All' -and -not $query) {
            $script:AllOptionsCountLabel.Text = ($total.ToString() + ' settings')
        } else {
            $script:AllOptionsCountLabel.Text = ($shown.ToString() + ' of ' + $total.ToString() + ' settings')
        }
    }

    if ($script:AllOptionsEmptyState) {
        $script:AllOptionsEmptyState.Visible = ($shown -eq 0)
        if ($shown -eq 0) {
            $query = if ($script:AllOptionsSearch) { $script:AllOptionsSearch.Text.Trim() } else { '' }
            $filter = if ($script:AllOptionsFilter) { [string]$script:AllOptionsFilter } else { 'All' }
            if ($query) {
                $script:AllOptionsEmptyState.Text = ('No settings match "' + $query + '".')
            } elseif ($filter -eq 'Active') {
                $script:AllOptionsEmptyState.Text = 'No active options yet.'
            } elseif ($filter -eq 'Basic') {
                $script:AllOptionsEmptyState.Text = 'No Basic options.'
            } else {
                $script:AllOptionsEmptyState.Text = 'No settings to show.'
            }
        }
    }
}

function Update-AllOptionsAfterActiveChanged {
    param(
        [Parameter(Mandatory = $true)]
        $State
    )

    if (-not (& ${function:Get-IsAllOptionsSelected})) { return }

    if ($script:AllOptionsFilter -eq 'Active') {
        $stillActive = & ${function:Test-OptionEffectActive} -State $State
        & ${function:Refresh-AllOptionsList}
        if (-not $stillActive -and $script:AllOptionsSelectedState -and $script:AllOptionsSelectedState.Meta.Id -eq $State.Meta.Id) {
            & ${function:Clear-AllOptionsEditor}
        }
    } else {
        & ${function:Update-AllOptionsListItemForState} -State $State
    }
}

function Clear-AllOptionsSearch {
    if ($script:AllOptionsSearch -and $script:AllOptionsSearch.Text.Length -gt 0) {
        $script:AllOptionsSearch.Clear()
    } else {
        & ${function:Refresh-AllOptionsList}
    }
}

function Refresh-Preview {
    if (-not $script:txtPreview) { return }

    $exe = Quote-WindowsArgument $script:txtServer.Text
    $argLines = New-Object System.Collections.Generic.List[string]
    foreach ($token in (Get-ArgumentTokens)) {
        [void]$argLines.Add((Quote-WindowsArgument $token))
    }

    if ($argLines.Count -gt 0) {
        $script:txtPreview.Text = $exe + "`r`n    " + ([string]::Join("`r`n    ", $argLines))
    } else {
        $script:txtPreview.Text = $exe
    }

}

function Get-TabColumnLayout {
    param(
        [Parameter(Mandatory = $true)]
        $Page
    )

    $clientWidth = [Math]::Max(780, ($Page.ClientSize.Width - 18))
    $settingWidth = if ($clientWidth -ge 1380) {
        248
    } elseif ($clientWidth -ge 1200) {
        232
    } elseif ($clientWidth -ge 1040) {
        214
    } else {
        194
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
        'preset' { return [Math]::Max(180, [Math]::Min(($Columns.ValueWidth - 78), 360)) }
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

function Update-PreviewPanelLayout {
    if (-not $script:mainSplit) { return }

    $script:mainSplit.Panel2.SuspendLayout()
    try {
        $panelWidth = $script:mainSplit.Panel2.ClientSize.Width
        $panelHeight = $script:mainSplit.Panel2.ClientSize.Height
        $contentWidth = [Math]::Max(320, ($panelWidth - 20))
        $buttonsY = [Math]::Max(0, ($panelHeight - 40))

        if ($script:previewLabel) {
            $script:previewLabel.Location = [System.Drawing.Point]::new(10, 10)
        }

        if ($script:txtPreview) {
            $previewTop = 32
            $previewHeight = [Math]::Max(110, ($buttonsY - $previewTop - 8))
            $script:txtPreview.Location = [System.Drawing.Point]::new(10, $previewTop)
            $script:txtPreview.Size = [System.Drawing.Size]::new($contentWidth, $previewHeight)
        }

        if ($script:btnCopy) {
            $script:btnCopy.Location = [System.Drawing.Point]::new(10, $buttonsY)
            if ($script:btnSaveCmd) {
                $script:btnSaveCmd.Location = [System.Drawing.Point]::new(143, $buttonsY)
            }
            if ($script:btnReset) {
                $script:btnReset.Location = [System.Drawing.Point]::new(286, $buttonsY)
            }
            if ($script:btnLaunch) {
                $script:btnLaunch.Location = [System.Drawing.Point]::new([Math]::Max(460, ($panelWidth - 250)), ($buttonsY - 4))
            }
        }
    } finally {
        $script:mainSplit.Panel2.ResumeLayout($false)
    }
}

function Update-WindowLayout {
    param([switch]$ForceColumns)

    if (-not $script:form -or $script:form.IsDisposed) { return }
    if ($script:LayoutInProgress) {
        $script:LayoutRequested = $true
        return
    }

    $script:LayoutInProgress = $true
    $script:LayoutRequested = $false

    try {
        $clientWidth = [Math]::Max(1080, $script:form.ClientSize.Width)
        $clientHeight = [Math]::Max(680, $script:form.ClientSize.Height)
        $widthChanged = ($ForceColumns -or $script:LastLayoutWidth -ne $clientWidth)

        $script:form.SuspendLayout()
        if ($script:grpRequired) { $script:grpRequired.SuspendLayout() }
        if ($script:mainSplit) { $script:mainSplit.SuspendLayout() }

        if ($script:titleLabel) {
            $script:titleLabel.Size = [System.Drawing.Size]::new(($clientWidth - 30), 28)
        }

        if ($script:subtitleLabel) {
            $script:subtitleLabel.Size = [System.Drawing.Size]::new(($clientWidth - 30), 18)
        }

        if ($script:grpRequired) {
            $script:grpRequired.Location = [System.Drawing.Point]::new(10, 62)
            $script:grpRequired.Size = [System.Drawing.Size]::new(($clientWidth - 20), 88)

            $left = 14
            $wideLabelWidth = 128
            $inputX = 150
            $browseWidth = 92
            $buttonGap = 8
            $inputWidth = [Math]::Max(300, ($script:grpRequired.ClientSize.Width - $inputX - $browseWidth - 18))

            if ($script:lblServerRequired) {
                $script:lblServerRequired.Location = [System.Drawing.Point]::new($left, 29)
                $script:lblServerRequired.Size = [System.Drawing.Size]::new($wideLabelWidth, 20)
            }
            if ($script:txtServer) {
                $script:txtServer.Location = [System.Drawing.Point]::new($inputX, 26)
                $script:txtServer.Size = [System.Drawing.Size]::new($inputWidth, 25)
            }
            if ($script:btnServer) {
                $script:btnServer.Location = [System.Drawing.Point]::new(($inputX + $inputWidth + $buttonGap), 25)
                $script:btnServer.Size = [System.Drawing.Size]::new($browseWidth, 27)
            }
            if ($script:lblModel) {
                $script:lblModel.Location = [System.Drawing.Point]::new($left, 58)
                $script:lblModel.Size = [System.Drawing.Size]::new($wideLabelWidth, 20)
            }
            if ($script:txtModel) {
                $script:txtModel.Location = [System.Drawing.Point]::new($inputX, 55)
                $script:txtModel.Size = [System.Drawing.Size]::new($inputWidth, 25)
            }
            if ($script:btnModel) {
                $script:btnModel.Location = [System.Drawing.Point]::new(($inputX + $inputWidth + $buttonGap), 54)
                $script:btnModel.Size = [System.Drawing.Size]::new($browseWidth, 27)
            }
        }

        if ($script:mainSplit) {
            $splitTop = if ($script:grpRequired) { $script:grpRequired.Bottom + 10 } else { 190 }
            $splitHeight = [Math]::Max(320, ($clientHeight - $splitTop - 10))
            $script:mainSplit.Location = [System.Drawing.Point]::new(10, $splitTop)
            $script:mainSplit.Size = [System.Drawing.Size]::new(($clientWidth - 20), $splitHeight)

            $maxSplitter = [Math]::Max($script:mainSplit.Panel1MinSize, ($script:mainSplit.Height - $script:mainSplit.Panel2MinSize - $script:mainSplit.SplitterWidth))
            $targetSplitter = [Math]::Max($script:mainSplit.Panel1MinSize, [Math]::Min($script:mainSplit.SplitterDistance, $maxSplitter))
            if ($script:mainSplit.SplitterDistance -ne $targetSplitter) {
                $script:mainSplit.SplitterDistance = $targetSplitter
            }
        }

        Update-PreviewPanelLayout

        if ($widthChanged) {
            & ${function:Update-QuickSetupLayout}
        }

        & ${function:Update-AllOptionsPageLayout}

        $script:LastLayoutWidth = $clientWidth
    } finally {
        if ($script:mainSplit) { $script:mainSplit.ResumeLayout($false) }
        if ($script:grpRequired) { $script:grpRequired.ResumeLayout($false) }
        if ($script:form) { $script:form.ResumeLayout($false) }
        $script:LayoutInProgress = $false
    }

    if ($script:LayoutRequested) {
        $script:LayoutRequested = $false
        Request-WindowLayout
    }
}

function Request-WindowLayout {
    if (-not $script:form -or $script:form.IsDisposed) { return }

    if (-not $script:LayoutTimer) {
        $layoutTimer = New-Object System.Windows.Forms.Timer
        $layoutTimer.Interval = 80
        $layoutTimer.Add_Tick({
            param($sender, $eventArgs)
            if ($sender) { $sender.Stop() }
            & ${function:Update-WindowLayout}
        }.GetNewClosure())
        $script:LayoutTimer = $layoutTimer
    }

    $script:LayoutTimer.Stop()
    $script:LayoutTimer.Start()
}

function Set-OptionRowVisible {
    param(
        [Parameter(Mandatory = $true)]
        $State,
        [bool]$Visible
    )

    if ($State.Meta.Type -eq 'preset') {
        $State.Override.Visible = $false
        if ($State.FlagLabel) { $State.FlagLabel.Visible = $Visible }
    } else {
        $State.Override.Visible = $Visible
        if ($State.FlagLabel) { $State.FlagLabel.Visible = $Visible }
    }
    if ($State.Label) { $State.Label.Visible = $Visible }
    if ($State.Control) { $State.Control.Visible = $Visible }
    if ($State.BrowseButton) { $State.BrowseButton.Visible = $Visible }
}

function Move-StateControlsToPage {
    param(
        [Parameter(Mandatory = $true)] $State,
        [Parameter(Mandatory = $true)] $TargetPage
    )

    if ($State.Override -and $State.Override.Parent -ne $TargetPage)         { [void]$TargetPage.Controls.Add($State.Override) }
    if ($State.Label -and $State.Label.Parent -ne $TargetPage)               { [void]$TargetPage.Controls.Add($State.Label) }
    if ($State.FlagLabel -and $State.FlagLabel.Parent -ne $TargetPage)       { [void]$TargetPage.Controls.Add($State.FlagLabel) }
    if ($State.Control -and $State.Control.Parent -ne $TargetPage)           { [void]$TargetPage.Controls.Add($State.Control) }
    if ($State.BrowseButton -and $State.BrowseButton.Parent -ne $TargetPage) { [void]$TargetPage.Controls.Add($State.BrowseButton) }
}

function Update-QuickSetupLayout {
    $page = $script:TabPages['QuickSetup']
    if (-not $page) { return }

    $page.SuspendLayout()

    $columns = & ${function:Get-TabColumnLayout} -Page $page

    $y = 14
    foreach ($group in $script:BasicLayout) {
        $rowsForGroup = New-Object System.Collections.Generic.List[object]
        foreach ($id in $group.Ids) {
            $state = Get-OptionStateById -Id $id
            if ($state) { [void]$rowsForGroup.Add($state) }
        }

        $sectionEntry = $script:QuickSetupSectionLabels | Where-Object { $_.Section -eq $group.Section } | Select-Object -First 1
        if ($rowsForGroup.Count -eq 0) {
            if ($sectionEntry) { $sectionEntry.Control.Visible = $false }
            continue
        }

        if ($sectionEntry) {
            $sectionEntry.Control.Visible = $true
            $sectionEntry.Control.Location = [System.Drawing.Point]::new($columns.SettingX, $y)
            $sectionEntry.Control.Size = [System.Drawing.Size]::new($columns.SectionWidth, 18)
        }
        $y += 22

        foreach ($state in $rowsForGroup) {
            & ${function:Move-StateControlsToPage} -State $state -TargetPage $page
            & ${function:Set-OptionRowVisible} -State $state -Visible $true

            $state.Override.Location = [System.Drawing.Point]::new($columns.Left, ($y + 2))
            $state.Label.Location = [System.Drawing.Point]::new($columns.SettingX, ($y + 3))
            $state.Label.Size = [System.Drawing.Size]::new($columns.SettingWidth, 20)
            if ($state.FlagLabel) {
                $state.FlagLabel.Location = [System.Drawing.Point]::new($columns.FlagX, ($y + 4))
                $state.FlagLabel.Size = [System.Drawing.Size]::new($columns.FlagWidth, 18)
            }
            if ($state.Control) {
                $controlWidth = & ${function:Get-OptionControlWidth} -State $state -Columns $columns
                $state.Control.Location = [System.Drawing.Point]::new($columns.ValueX, $y)
                $state.Control.Size = [System.Drawing.Size]::new($controlWidth, $state.Control.Height)
                if ($state.Control -is [System.Windows.Forms.ComboBox]) {
                    $state.Control.DropDownWidth = [Math]::Max($controlWidth, [Math]::Min(560, $columns.ValueWidth))
                }
                if ($state.BrowseButton) {
                    $state.BrowseButton.Location = [System.Drawing.Point]::new(($columns.ValueX + $controlWidth + 8), $y)
                }
            }
            $y += 32
        }
        $y += 12
    }

    $page.AutoScrollMinSize = [System.Drawing.Size]::new(0, [Math]::Max(0, ($y + 12)))
    $page.ResumeLayout()
}

function Update-MainTabs {
    $selectedTabKey = if ($script:MainTabs -and $script:MainTabs.SelectedTab) { [string]$script:MainTabs.SelectedTab.Tag } else { '' }
    $visibleTabs = New-Object System.Collections.Generic.List[string]

    if ($script:AllOptionsSelectedState) {
        & ${function:Restore-AllOptionsEditorSelection}
    }

    foreach ($state in $script:OptionStates) {
        if (-not $state.Meta.Basic) {
            & ${function:Set-OptionRowVisible} -State $state -Visible $false
        }
    }
    & ${function:Update-QuickSetupLayout}

    [void]$visibleTabs.Add('QuickSetup')
    [void]$visibleTabs.Add('AllOptions')

    if ($script:MainTabs) {
        $script:SuppressMainTabEvents = $true
        $script:MainTabs.SuspendLayout()
        try {
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
        } finally {
            $script:MainTabs.ResumeLayout()
            $script:SuppressMainTabEvents = $false
        }
    }

    & ${function:Update-WindowLayout}
    & ${function:Refresh-Preview}
    if (& ${function:Get-IsAllOptionsSelected}) {
        & ${function:Refresh-AllOptionsList}
        if ($script:AllOptionsSearch) {
            [void]$script:AllOptionsSearch.Focus()
        }
    }
    $script:LastMainTabKey = if ($script:MainTabs -and $script:MainTabs.SelectedTab) { [string]$script:MainTabs.SelectedTab.Tag } else { '' }
}

function Get-OptionStateById {
    param([string]$Id)
    return $script:OptionStatesById[$Id]
}

function Apply-SamplerPreset {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    if (-not $script:SamplerPresets.Contains($Name)) { return }

    $values = $script:SamplerPresets[$Name]
    if ($null -eq $values) { return }

    $script:ApplyingSamplerPreset = $true
    try {
        foreach ($id in $values.Keys) {
            $state = Get-OptionStateById -Id $id
            if (-not $state) { continue }

            $value = $values[$id]
            switch ($state.Meta.Type) {
                'decimal' {
                    $state.Control.Value = [decimal]$value
                }
                'number' {
                    $state.Control.Value = [decimal]$value
                }
                default {
                    $state.Control.Text = [string]$value
                }
            }
            $state.Override.Checked = $true
        }
    } finally {
        $script:ApplyingSamplerPreset = $false
    }

    & ${function:Refresh-Preview}
    if (& ${function:Get-IsAllOptionsSelected}) {
        & ${function:Refresh-AllOptionsList}
    }
}

function Clear-ComboTextSelection {
    param($Control)

    if ($Control -and $Control -is [System.Windows.Forms.ComboBox] -and $Control.DropDownStyle -eq [System.Windows.Forms.ComboBoxStyle]::DropDown) {
        $Control.SelectionStart = $Control.Text.Length
        $Control.SelectionLength = 0
    }
}

function Reset-OptionValueToDefault {
    param(
        [Parameter(Mandatory = $true)]
        $State
    )

    if (-not $State.Control) { return }

    $default = $State.Meta.Default
    switch ($State.Meta.Type) {
        'number' {
            $value = if ($default -ne $null) { [decimal]$default } else { [decimal]$State.Control.Minimum }
            if ($value -lt $State.Control.Minimum) { $value = $State.Control.Minimum }
            if ($value -gt $State.Control.Maximum) { $value = $State.Control.Maximum }
            $State.Control.Value = $value
        }
        'decimal' {
            $value = if ($default -ne $null) { [decimal]$default } else { [decimal]$State.Control.Minimum }
            if ($value -lt $State.Control.Minimum) { $value = $State.Control.Minimum }
            if ($value -gt $State.Control.Maximum) { $value = $State.Control.Maximum }
            $State.Control.Value = $value
        }
        'combo' {
            if ($default -ne $null) {
                $text = [string]$default
                if ($State.Control.Items.Contains($text)) {
                    $State.Control.SelectedItem = $text
                } else {
                    $State.Control.Text = $text
                }
            } elseif ($State.Control.Items.Count -gt 0) {
                $State.Control.SelectedIndex = 0
            } else {
                $State.Control.Text = ''
            }
            & ${function:Clear-ComboTextSelection} -Control $State.Control
        }
        'pair' {
            $State.Control.SelectedItem = if ($default) { [string]$default } else { 'Enabled' }
        }
        'flagchoice' {
            if ($default -and $State.Control.Items.Contains([string]$default)) {
                $State.Control.SelectedItem = [string]$default
            } elseif ($State.Control.Items.Count -gt 0) {
                $State.Control.SelectedIndex = 0
            }
        }
        'preset' {
            if ($default -and $State.Control.Items.Contains([string]$default)) {
                $State.Control.SelectedItem = [string]$default
            } elseif ($State.Control.Items.Count -gt 0) {
                $State.Control.SelectedIndex = 0
            }
        }
        default {
            $State.Control.Text = if ($default -ne $null) { [string]$default } else { '' }
        }
    }
}

function Reset-AllOverrides {
    $script:ApplyingSamplerPreset = $true
    try {
        foreach ($state in $script:OptionStates) {
            & ${function:Reset-OptionValueToDefault} -State $state
            if ($state.Meta.Type -eq 'preset') { continue }
            $state.Override.Checked = $false
        }
    } finally {
        $script:ApplyingSamplerPreset = $false
    }
    & ${function:Refresh-Preview}
    if (& ${function:Get-IsAllOptionsSelected}) {
        & ${function:Refresh-AllOptionsList}
    }
}

function Get-ToolWorkingDir {
    $state = Get-OptionStateById -Id 'tool_working_dir'
    if (-not $state) { return '' }
    if (-not $state.Override.Checked) { return '' }
    return [string]$state.Control.Text
}

function Test-LaunchValid {
    if ([string]::IsNullOrWhiteSpace($script:txtServer.Text) -or -not (Test-Path -LiteralPath $script:txtServer.Text -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show(
            'Please select a valid llama-server.exe.',
            'Missing Server',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return $false
    }

    if ((& ${function:Should-IncludeModelPath}) -and -not (Test-Path -LiteralPath $script:txtModel.Text -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show(
            'The selected local model path does not exist. Clear it if you intend to use an alternative model source instead.',
            'Invalid Model Path',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return $false
    }

    $toolDir = & ${function:Get-ToolWorkingDir}
    if (-not [string]::IsNullOrWhiteSpace($toolDir) -and -not (Test-Path -LiteralPath $toolDir -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show(
            'The selected tool working folder does not exist or is not a folder.',
            'Invalid Tool Working Folder',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return $false
    }

    foreach ($state in $script:OptionStates) {
        if (-not $state.Override.Checked) { continue }
        $arity = if ($state.Meta.Arity) { [int]$state.Meta.Arity } else { 1 }
        if ($arity -le 1) { continue }
        if (-not $state.Control) { continue }
        $rawText = [string]$state.Control.Text
        if ([string]::IsNullOrWhiteSpace($rawText)) { continue }
        $partCount = ($rawText.Trim() -split '\s+').Count
        if ($partCount -ne $arity) {
            [System.Windows.Forms.MessageBox]::Show(
                ('{0} expects exactly {1} whitespace-separated values, but got {2}: "{3}".' -f $state.Meta.Label, $arity, $partCount, $rawText),
                'Invalid Multi-Value Option',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return $false
        }
    }

    $kwargsState = Get-OptionStateById -Id 'chat_template_kwargs'
    if ($kwargsState -and $kwargsState.Override.Checked) {
        $kwargsText = [string]$kwargsState.Control.Text
        if (-not [string]::IsNullOrWhiteSpace($kwargsText)) {
            $parsed = $null
            try { $parsed = ConvertFrom-Json -InputObject $kwargsText -ErrorAction Stop } catch { $parsed = $null }
            $isJsonObject = ($null -ne $parsed) -and ($parsed.GetType().FullName -eq 'System.Management.Automation.PSCustomObject')
            if (-not $isJsonObject) {
                [System.Windows.Forms.MessageBox]::Show(
                    ('Chat Template Kwargs JSON is not a valid JSON object. Expected something like {"foo": true}, got: ' + $kwargsText),
                    'Invalid Chat Template Kwargs',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                return $false
            }
        }
    }

    return $true
}

function Build-SavedCommandText {
    $exe = & ${function:Quote-CmdArgument} $script:txtServer.Text
    $argTokens = & ${function:Get-ArgumentTokens}
    $quotedArgs = New-Object System.Collections.Generic.List[string]
    foreach ($t in $argTokens) {
        [void]$quotedArgs.Add((& ${function:Quote-CmdArgument} $t))
    }

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('@echo off')
    [void]$lines.Add('setlocal EnableExtensions DisableDelayedExpansion')
    [void]$lines.Add('chcp 65001 >nul')
    [void]$lines.Add('')

    $toolDir = & ${function:Get-ToolWorkingDir}
    if (-not [string]::IsNullOrWhiteSpace($toolDir)) {
        $cdPath = $toolDir -replace '%', '%%'
        [void]$lines.Add('cd /d "' + $cdPath + '"')
        [void]$lines.Add('')
    }

    if ($quotedArgs.Count -eq 0) {
        [void]$lines.Add($exe)
    } else {
        $lastIdx = $quotedArgs.Count - 1
        [void]$lines.Add($exe + ' ^')
        for ($i = 0; $i -lt $quotedArgs.Count; $i++) {
            $suffix = if ($i -lt $lastIdx) { ' ^' } else { '' }
            [void]$lines.Add('    ' + $quotedArgs[$i] + $suffix)
        }
    }

    [void]$lines.Add('')
    [void]$lines.Add('if errorlevel 1 pause')

    return ($lines -join "`r`n") + "`r`n"
}

function Add-OptionRow {
    param(
        [Parameter(Mandatory = $true)]
        $Option
    )

    $page = $script:TabPages[$Option.Tab]
    $layout = $script:TabLayouts[$Option.Tab]
    $controlLeft = 405

    $rowHeight = 32
    $checkbox = New-Object System.Windows.Forms.CheckBox
    $checkbox.Location = [System.Drawing.Point]::new(10, ($layout.Y + 2))
    $checkbox.Size = [System.Drawing.Size]::new(16, 20)
    $checkbox.Checked = $false
    $checkbox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $page.Controls.Add($checkbox)

    $label = $null
    $flagLabel = $null
    if ($Option.Basic) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $Option.Label
        $label.Location = [System.Drawing.Point]::new(38, ($layout.Y + 3))
        $label.Size = [System.Drawing.Size]::new(150, 20)
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
    }

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
            $control.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
            $control.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            foreach ($choice in $Option.Choices) {
                [void]$control.Items.Add($choice)
            }
            if ($Option.Default -ne $null) {
                $control.Text = [string]$Option.Default
                if (-not $Option.Editable) {
                    $control.SelectedItem = [string]$Option.Default
                }
                & ${function:Clear-ComboTextSelection} -Control $control
            }
            $control.Enabled = $false
            $page.Controls.Add($control)
            & ${function:Clear-ComboTextSelection} -Control $control
        }
        'preset' {
            $control = New-Object System.Windows.Forms.ComboBox
            $control.Location = [System.Drawing.Point]::new($controlLeft, $layout.Y)
            $control.Size = [System.Drawing.Size]::new(300, 24)
            $control.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $control.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
            $control.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            foreach ($choice in $Option.Choices) {
                [void]$control.Items.Add($choice)
            }
            if ($Option.Default -ne $null) {
                $control.SelectedItem = [string]$Option.Default
            } elseif ($control.Items.Count -gt 0) {
                $control.SelectedIndex = 0
            }
            $control.Enabled = $true
            $page.Controls.Add($control)

            $localControl = $control
            $browseButton = New-Object System.Windows.Forms.Button
            $browseButton.Text = 'Apply'
            $browseButton.Location = [System.Drawing.Point]::new(714, $layout.Y)
            $browseButton.Size = [System.Drawing.Size]::new(70, 24)
            $browseButton.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
            $browseButton.Enabled = $false
            $browseButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            $browseButton.Add_Click({
                $sel = [string]$localControl.SelectedItem
                & ${function:Apply-SamplerPreset} -Name $sel
            }.GetNewClosure())
            $localButton = $browseButton
            $localDefault = [string]$Option.Default
            $control.Add_SelectedIndexChanged({
                $sel = [string]$localControl.SelectedItem
                $localButton.Enabled = (-not [string]::IsNullOrWhiteSpace($sel) -and $sel -ne $localDefault)
            }.GetNewClosure())
            $page.Controls.Add($browseButton)
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
        { $_ -in 'path', 'folder' } {
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
                $isFolder = ($localOption.Type -eq 'folder')
                $startDir = if ($localControl.Text -and (Test-Path -LiteralPath $localControl.Text)) {
                    if ($isFolder) { $localControl.Text } else { Split-Path -Parent $localControl.Text }
                } else { $script:BatDir }
                $mode = if ($isFolder) { 'folder' } else { $localOption.BrowseMode }
                $selected = & ${function:Browse-Path} -Title ('Select ' + $localOption.Label) -Mode $mode -Filter $localOption.Filter -StartDir $startDir
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
    & ${function:Register-OptionHelp} -State $state

    $localState = $state
    if ($Option.Type -eq 'preset') {
        $checkbox.Checked = $true
        $checkbox.Visible = $false
        if ($label) { $label.ForeColor = [System.Drawing.Color]::FromArgb(35, 35, 35) }
        if ($flagLabel) { $flagLabel.ForeColor = [System.Drawing.Color]::FromArgb(95, 95, 95) }
    } else {
        $checkbox.Add_CheckedChanged({
            $enabled = $localState.Override.Checked
            if ($localState.Label) {
                $localState.Label.ForeColor = if ($enabled) { [System.Drawing.Color]::FromArgb(35, 35, 35) } else { [System.Drawing.Color]::FromArgb(160, 160, 160) }
            }
            if ($localState.FlagLabel) {
                $localState.FlagLabel.ForeColor = if ($enabled) { [System.Drawing.Color]::FromArgb(75, 75, 75) } else { [System.Drawing.Color]::FromArgb(145, 145, 145) }
            }
            if ($localState.Control) {
                if ($localState.Meta.Type -eq 'combo' -and $localState.Meta.Editable -and $localState.Control -is [System.Windows.Forms.ComboBox]) {
                    $localState.Control.DropDownStyle = if ($enabled) { [System.Windows.Forms.ComboBoxStyle]::DropDown } else { [System.Windows.Forms.ComboBoxStyle]::DropDownList }
                }
                $localState.Control.Enabled = $enabled
                if (-not $enabled) { & ${function:Clear-ComboTextSelection} -Control $localState.Control }
            }
            if ($localState.BrowseButton) { $localState.BrowseButton.Enabled = $enabled }
            if (-not $script:ApplyingSamplerPreset) {
                & ${function:Refresh-Preview}
                & ${function:Update-AllOptionsAfterActiveChanged} -State $localState
            }
        }.GetNewClosure())

        if ($control) {
            $autoTickHandler = {
                if ($script:ApplyingSamplerPreset) { return }
                if ($localState.Control -and -not $localState.Control.Enabled) { return }
                $wasChecked = $localState.Override.Checked
                if (-not $wasChecked) {
                    $localState.Override.Checked = $true
                }
                if ($wasChecked) {
                    & ${function:Refresh-Preview}
                }
            }.GetNewClosure()
            switch ($Option.Type) {
                'number'      { $control.Add_ValueChanged($autoTickHandler) }
                'decimal'     { $control.Add_ValueChanged($autoTickHandler) }
                'combo'       { $control.Add_TextChanged($autoTickHandler); $control.Add_SelectedIndexChanged($autoTickHandler) }
                'pair'        { $control.Add_SelectedIndexChanged($autoTickHandler) }
                'flagchoice'  { $control.Add_SelectedIndexChanged($autoTickHandler) }
                default       { $control.Add_TextChanged($autoTickHandler) }
            }
        }
    }

    $layout.Y += $rowHeight
}

$tabSpecs = @(
    @{ Key = 'QuickSetup';  Title = 'Quick Setup' },
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

$script:BasicLayout = @(
    @{ Section = 'Server & Network';        Ids = @('host', 'port', 'api_key') },
    @{ Section = 'Model Source';            Ids = @('hf_repo', 'hf_file') },
    @{ Section = 'Sampling Preset';         Ids = @('sampler_preset') },
    @{ Section = 'Response Behavior';       Ids = @('temp', 'top_k', 'top_p', 'min_p', 'repeat_penalty', 'presence_penalty', 'seed') },
    @{ Section = 'Thinking & Templates';    Ids = @('reasoning', 'reasoning_budget', 'enable_thinking', 'preserve_thinking', 'chat_template', 'jinja') },
    @{ Section = 'Hardware & Memory';       Ids = @('n_gpu_layers', 'fit', 'ctx_size', 'batch_size', 'flash_attn', 'cache_type_v', 'threads') },
    @{ Section = 'Multimodal';              Ids = @('mmproj') },
    @{ Section = 'Agent Tools';             Ids = @('tools', 'tool_working_dir') },
    @{ Section = 'Router Mode';             Ids = @('models_dir', 'models_preset', 'models_max', 'models_autoload') }
)
$script:QuickSetupSectionLabels = [System.Collections.ArrayList]::new()

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

Add-OptionMeta (New-OptionMeta -Id 'host' -Tab 'Server' -Section 'Network' -Label 'Host / Bind Address' -Type 'text' -Flag '--host' -Default '127.0.0.1' -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'port' -Tab 'Server' -Section 'Network' -Label 'Port' -Type 'number' -Flag '--port' -Default 8080 -Min 1 -Max 65535 -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'reuse_port' -Tab 'Server' -Section 'Network' -Label 'Reuse Port' -Type 'flag' -Flag '--reuse-port')
Add-OptionMeta (New-OptionMeta -Id 'timeout' -Tab 'Server' -Section 'Network' -Label 'Read/Write Timeout (s)' -Type 'number' -Flag '--timeout' -Default 600 -Min 1 -Max 86400)
Add-OptionMeta (New-OptionMeta -Id 'threads_http' -Tab 'Server' -Section 'Network' -Label 'HTTP Threads' -Type 'number' -Flag '--threads-http' -Default -1 -Min -1 -Max 256)
Add-OptionMeta (New-OptionMeta -Id 'api_prefix' -Tab 'Server' -Section 'Network' -Label 'API Prefix' -Type 'text' -Flag '--api-prefix')
Add-OptionMeta (New-OptionMeta -Id 'static_path' -Tab 'Server' -Section 'Web UI and Static Files' -Label 'Static Files Path' -Type 'folder' -Flag '--path' -BrowseMode 'folder')
Add-OptionMeta (New-OptionMeta -Id 'webui' -Tab 'Server' -Section 'Web UI and Static Files' -Label 'Web UI' -Type 'pair' -Flag '--webui' -NegFlag '--no-webui' -Default 'Enabled')
Add-OptionMeta (New-OptionMeta -Id 'webui_config' -Tab 'Server' -Section 'Web UI and Static Files' -Label 'Web UI Config JSON' -Type 'text' -Flag '--webui-config')
Add-OptionMeta (New-OptionMeta -Id 'webui_config_file' -Tab 'Server' -Section 'Web UI and Static Files' -Label 'Web UI Config File' -Type 'path' -Flag '--webui-config-file' -BrowseMode 'file' -Filter 'JSON files (*.json)|*.json|All files (*.*)|*.*')
Add-OptionMeta (New-OptionMeta -Id 'webui_mcp_proxy' -Tab 'Server' -Section 'Web UI and Static Files' -Label 'Web UI MCP Proxy' -Type 'pair' -Flag '--webui-mcp-proxy' -NegFlag '--no-webui-mcp-proxy' -Default 'Disabled')
Add-OptionMeta (New-OptionMeta -Id 'tools' -Tab 'Server' -Section 'Agent Tools' -Label 'Built-in Tools' -Type 'text' -Flag '--tools' -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'tool_working_dir' -Tab 'Server' -Section 'Agent Tools' -Label 'Tool Working Folder' -Type 'folder' -Flag '' -BrowseMode 'folder' -Filter 'All folders|*.*' -Basic $true -DisplayFlag 'Launcher: tool cwd' -Kind 'Launcher')
Add-OptionMeta (New-OptionMeta -Id 'api_key' -Tab 'Server' -Section 'Authentication and TLS' -Label 'API Key(s)' -Type 'text' -Flag '--api-key' -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'api_key_file' -Tab 'Server' -Section 'Authentication and TLS' -Label 'API Key File' -Type 'path' -Flag '--api-key-file' -BrowseMode 'file' -Filter 'Text files (*.txt)|*.txt|All files (*.*)|*.*')
Add-OptionMeta (New-OptionMeta -Id 'ssl_key_file' -Tab 'Server' -Section 'Authentication and TLS' -Label 'SSL Key File' -Type 'path' -Flag '--ssl-key-file' -BrowseMode 'file' -Filter 'PEM files (*.pem)|*.pem|All files (*.*)|*.*')
Add-OptionMeta (New-OptionMeta -Id 'ssl_cert_file' -Tab 'Server' -Section 'Authentication and TLS' -Label 'SSL Certificate File' -Type 'path' -Flag '--ssl-cert-file' -BrowseMode 'file' -Filter 'PEM/CRT files (*.pem;*.crt)|*.pem;*.crt|All files (*.*)|*.*')
Add-OptionMeta (New-OptionMeta -Id 'metrics' -Tab 'Server' -Section 'Monitoring and Endpoints' -Label 'Metrics Endpoint' -Type 'flag' -Flag '--metrics')
Add-OptionMeta (New-OptionMeta -Id 'props' -Tab 'Server' -Section 'Monitoring and Endpoints' -Label 'Props Endpoint' -Type 'flag' -Flag '--props')
Add-OptionMeta (New-OptionMeta -Id 'slots' -Tab 'Server' -Section 'Monitoring and Endpoints' -Label 'Slots Endpoint' -Type 'pair' -Flag '--slots' -NegFlag '--no-slots' -Default 'Enabled')
Add-OptionMeta (New-OptionMeta -Id 'slot_save_path' -Tab 'Server' -Section 'Monitoring and Endpoints' -Label 'Slot Save Path' -Type 'folder' -Flag '--slot-save-path' -BrowseMode 'folder')
Add-OptionMeta (New-OptionMeta -Id 'media_path' -Tab 'Server' -Section 'Monitoring and Endpoints' -Label 'Media Path' -Type 'folder' -Flag '--media-path' -BrowseMode 'folder')

Add-OptionMeta (New-OptionMeta -Id 'model_url' -Tab 'Model' -Section 'Alternative Model Sources' -Label 'Model URL' -Type 'text' -Flag '--model-url')
Add-OptionMeta (New-OptionMeta -Id 'docker_repo' -Tab 'Model' -Section 'Alternative Model Sources' -Label 'Docker Repo' -Type 'text' -Flag '--docker-repo')
Add-OptionMeta (New-OptionMeta -Id 'hf_repo' -Tab 'Model' -Section 'Alternative Model Sources' -Label 'Hugging Face Repo' -Type 'text' -Flag '--hf-repo' -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'hf_file' -Tab 'Model' -Section 'Alternative Model Sources' -Label 'Hugging Face File' -Type 'text' -Flag '--hf-file' -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'hf_token' -Tab 'Model' -Section 'Alternative Model Sources' -Label 'Hugging Face Token' -Type 'text' -Flag '--hf-token')
Add-OptionMeta (New-OptionMeta -Id 'offline' -Tab 'Model' -Section 'Alternative Model Sources' -Label 'Offline Mode' -Type 'flag' -Flag '--offline')
Add-OptionMeta (New-OptionMeta -Id 'alias' -Tab 'Model' -Section 'Metadata' -Label 'Alias' -Type 'text' -Flag '--alias')
Add-OptionMeta (New-OptionMeta -Id 'tags' -Tab 'Model' -Section 'Metadata' -Label 'Tags' -Type 'text' -Flag '--tags')
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
) -DisplayFlag '--embd-gemma-default / --fim-qwen-* / --gpt-oss-* / --vision-gemma-*')
Add-OptionMeta (New-OptionMeta -Id 'utility_action' -Tab 'Model' -Section 'Utilities' -Label 'Utility Command' -Type 'flagchoice' -Choices @(
    (New-Choice 'Show help and exit' '--help'),
    (New-Choice 'Show version and exit' '--version'),
    (New-Choice 'Show license and exit' '--license'),
    (New-Choice 'Show cache list and exit' '--cache-list'),
    (New-Choice 'Print bash completion and exit' '--completion-bash'),
    (New-Choice 'List devices and exit' '--list-devices')
) -DisplayFlag '--help / --version / --license / --cache-list / --completion-bash / --list-devices')

Add-OptionMeta (New-OptionMeta -Id 'threads' -Tab 'Performance' -Section 'CPU and Threading' -Label 'CPU Threads' -Type 'number' -Flag '--threads' -Default -1 -Min -1 -Max 256 -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'threads_batch' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Batch Threads' -Type 'number' -Flag '--threads-batch' -Default -1 -Min -1 -Max 256)
Add-OptionMeta (New-OptionMeta -Id 'cpu_mask' -Tab 'Performance' -Section 'CPU and Threading' -Label 'CPU Mask' -Type 'text' -Flag '--cpu-mask')
Add-OptionMeta (New-OptionMeta -Id 'cpu_range' -Tab 'Performance' -Section 'CPU and Threading' -Label 'CPU Range' -Type 'text' -Flag '--cpu-range')
Add-OptionMeta (New-OptionMeta -Id 'cpu_strict' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Strict CPU Placement' -Type 'combo' -Flag '--cpu-strict' -Choices @('0', '1') -Default '0')
Add-OptionMeta (New-OptionMeta -Id 'prio' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Priority' -Type 'combo' -Flag '--prio' -Choices @('-1', '0', '1', '2', '3') -Default '0')
Add-OptionMeta (New-OptionMeta -Id 'poll' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Polling Level' -Type 'number' -Flag '--poll' -Default 50 -Min 0 -Max 100)
Add-OptionMeta (New-OptionMeta -Id 'cpu_mask_batch' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Batch CPU Mask' -Type 'text' -Flag '--cpu-mask-batch')
Add-OptionMeta (New-OptionMeta -Id 'cpu_range_batch' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Batch CPU Range' -Type 'text' -Flag '--cpu-range-batch')
Add-OptionMeta (New-OptionMeta -Id 'cpu_strict_batch' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Strict Batch Placement' -Type 'combo' -Flag '--cpu-strict-batch' -Choices @('0', '1') -Default '0')
Add-OptionMeta (New-OptionMeta -Id 'prio_batch' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Batch Priority' -Type 'combo' -Flag '--prio-batch' -Choices @('0', '1', '2', '3') -Default '0')
Add-OptionMeta (New-OptionMeta -Id 'poll_batch' -Tab 'Performance' -Section 'CPU and Threading' -Label 'Batch Polling' -Type 'combo' -Flag '--poll-batch' -Choices @('0', '1') -Default '0')
Add-OptionMeta (New-OptionMeta -Id 'ctx_size' -Tab 'Performance' -Section 'Context and Memory' -Label 'Context Size' -Type 'number' -Flag '--ctx-size' -Default 0 -Min 0 -Max 1048576 -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'predict' -Tab 'Performance' -Section 'Context and Memory' -Label 'Predict Tokens' -Type 'number' -Flag '--predict' -Default -1 -Min -1 -Max 1000000)
Add-OptionMeta (New-OptionMeta -Id 'keep' -Tab 'Performance' -Section 'Context and Memory' -Label 'Keep Tokens' -Type 'number' -Flag '--keep' -Default 0 -Min -1 -Max 1000000)
Add-OptionMeta (New-OptionMeta -Id 'batch_size' -Tab 'Performance' -Section 'Context and Memory' -Label 'Batch Size' -Type 'number' -Flag '--batch-size' -Default 2048 -Min 1 -Max 65536 -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'ubatch_size' -Tab 'Performance' -Section 'Context and Memory' -Label 'Micro Batch Size' -Type 'number' -Flag '--ubatch-size' -Default 512 -Min 1 -Max 65536)
Add-OptionMeta (New-OptionMeta -Id 'swa_full' -Tab 'Performance' -Section 'Context and Memory' -Label 'Full-size SWA Cache' -Type 'flag' -Flag '--swa-full')
Add-OptionMeta (New-OptionMeta -Id 'flash_attn' -Tab 'Performance' -Section 'Context and Memory' -Label 'Flash Attention' -Type 'combo' -Flag '--flash-attn' -Choices @('auto', 'on', 'off') -Default 'auto' -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'perf' -Tab 'Performance' -Section 'Context and Memory' -Label 'libllama Perf Timings' -Type 'pair' -Flag '--perf' -NegFlag '--no-perf' -Default 'Disabled')
Add-OptionMeta (New-OptionMeta -Id 'escape' -Tab 'Performance' -Section 'Context and Memory' -Label 'Escape Sequences' -Type 'pair' -Flag '--escape' -NegFlag '--no-escape' -Default 'Enabled')
Add-OptionMeta (New-OptionMeta -Id 'rope_scaling' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'RoPE Scaling' -Type 'combo' -Flag '--rope-scaling' -Choices @('none', 'linear', 'yarn') -Default 'linear')
Add-OptionMeta (New-OptionMeta -Id 'rope_scale' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'RoPE Scale' -Type 'decimal' -Flag '--rope-scale' -Default 1.00 -Min 0.00 -Max 100.00 -Increment 0.05 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'rope_freq_base' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'RoPE Freq Base' -Type 'number' -Flag '--rope-freq-base' -Default 10000 -Min 0 -Max 100000000)
Add-OptionMeta (New-OptionMeta -Id 'rope_freq_scale' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'RoPE Freq Scale' -Type 'decimal' -Flag '--rope-freq-scale' -Default 1.00 -Min 0.00 -Max 100.00 -Increment 0.05 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'yarn_orig_ctx' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'YaRN Original Context' -Type 'number' -Flag '--yarn-orig-ctx' -Default 0 -Min 0 -Max 1048576)
Add-OptionMeta (New-OptionMeta -Id 'yarn_ext_factor' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'YaRN Extrapolation Factor' -Type 'decimal' -Flag '--yarn-ext-factor' -Default -1.00 -Min -100.00 -Max 100.00 -Increment 0.05 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'yarn_attn_factor' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'YaRN Attention Factor' -Type 'decimal' -Flag '--yarn-attn-factor' -Default -1.00 -Min -100.00 -Max 100.00 -Increment 0.05 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'yarn_beta_slow' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'YaRN Beta Slow' -Type 'decimal' -Flag '--yarn-beta-slow' -Default -1.00 -Min -100.00 -Max 100.00 -Increment 0.05 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'yarn_beta_fast' -Tab 'Performance' -Section 'RoPE and YaRN' -Label 'YaRN Beta Fast' -Type 'decimal' -Flag '--yarn-beta-fast' -Default -1.00 -Min -100.00 -Max 100.00 -Increment 0.05 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'kv_offload' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'KV Offload' -Type 'pair' -Flag '--kv-offload' -NegFlag '--no-kv-offload' -Default 'Enabled')
Add-OptionMeta (New-OptionMeta -Id 'repack' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Weight Repacking' -Type 'pair' -Flag '--repack' -NegFlag '--no-repack' -Default 'Enabled')
Add-OptionMeta (New-OptionMeta -Id 'no_host' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Bypass Host Buffer' -Type 'flag' -Flag '--no-host')
Add-OptionMeta (New-OptionMeta -Id 'cache_type_k' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Cache Type K' -Type 'combo' -Flag '--cache-type-k' -Choices $cacheTypes -Default 'f16')
Add-OptionMeta (New-OptionMeta -Id 'cache_type_v' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Cache Type V' -Type 'combo' -Flag '--cache-type-v' -Choices $cacheTypes -Default 'f16' -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'defrag_thold' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Defrag Threshold (deprecated)' -Type 'decimal' -Flag '--defrag-thold' -Default 0.10 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'mlock' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Lock in RAM' -Type 'flag' -Flag '--mlock')
Add-OptionMeta (New-OptionMeta -Id 'mmap' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Memory Map Model' -Type 'pair' -Flag '--mmap' -NegFlag '--no-mmap' -Default 'Enabled')
Add-OptionMeta (New-OptionMeta -Id 'direct_io' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'Direct I/O' -Type 'pair' -Flag '--direct-io' -NegFlag '--no-direct-io' -Default 'Disabled')
Add-OptionMeta (New-OptionMeta -Id 'numa' -Tab 'Performance' -Section 'Memory Mapping and KV Cache' -Label 'NUMA Strategy' -Type 'combo' -Flag '--numa' -Choices @('distribute', 'isolate', 'numactl') -Default 'distribute')
Add-OptionMeta (New-OptionMeta -Id 'device' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Device(s)' -Type 'text' -Flag '--device')
Add-OptionMeta (New-OptionMeta -Id 'override_tensor' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Override Tensor Buffer' -Type 'text' -Flag '--override-tensor')
Add-OptionMeta (New-OptionMeta -Id 'cpu_moe' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Keep All MoE on CPU' -Type 'flag' -Flag '--cpu-moe')
Add-OptionMeta (New-OptionMeta -Id 'n_cpu_moe' -Tab 'Performance' -Section 'Devices and Offload' -Label 'CPU MoE Layers' -Type 'number' -Flag '--n-cpu-moe' -Default 0 -Min 0 -Max 10000)
Add-OptionMeta (New-OptionMeta -Id 'n_gpu_layers' -Tab 'Performance' -Section 'Devices and Offload' -Label 'GPU Layers' -Type 'combo' -Flag '--n-gpu-layers' -Choices @('auto', 'all', '0', '16', '32', '64', '99', '999') -Default 'auto' -Editable $true -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'split_mode' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Split Mode' -Type 'combo' -Flag '--split-mode' -Choices @('none', 'layer', 'row') -Default 'layer' -Editable $true)
Add-OptionMeta (New-OptionMeta -Id 'tensor_split' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Tensor Split' -Type 'text' -Flag '--tensor-split')
Add-OptionMeta (New-OptionMeta -Id 'main_gpu' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Main GPU' -Type 'number' -Flag '--main-gpu' -Default 0 -Min 0 -Max 32)
Add-OptionMeta (New-OptionMeta -Id 'fit' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Auto Fit to Memory' -Type 'combo' -Flag '--fit' -Choices @('on', 'off') -Default 'on' -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'fit_target' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Fit Target (MiB)' -Type 'text' -Flag '--fit-target')
Add-OptionMeta (New-OptionMeta -Id 'fit_ctx' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Fit Minimum Context' -Type 'number' -Flag '--fit-ctx' -Default 4096 -Min 0 -Max 1048576)
Add-OptionMeta (New-OptionMeta -Id 'check_tensors' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Check Tensors' -Type 'flag' -Flag '--check-tensors')
Add-OptionMeta (New-OptionMeta -Id 'override_kv' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Override KV Metadata' -Type 'text' -Flag '--override-kv')
Add-OptionMeta (New-OptionMeta -Id 'op_offload' -Tab 'Performance' -Section 'Devices and Offload' -Label 'Host Tensor Op Offload' -Type 'pair' -Flag '--op-offload' -NegFlag '--no-op-offload' -Default 'Enabled')
Add-OptionMeta (New-OptionMeta -Id 'lora' -Tab 'Performance' -Section 'Adapters and Control Vectors' -Label 'LoRA Adapter(s)' -Type 'text' -Flag '--lora')
Add-OptionMeta (New-OptionMeta -Id 'lora_scaled' -Tab 'Performance' -Section 'Adapters and Control Vectors' -Label 'Scaled LoRA Adapter(s)' -Type 'text' -Flag '--lora-scaled')
Add-OptionMeta (New-OptionMeta -Id 'control_vector' -Tab 'Performance' -Section 'Adapters and Control Vectors' -Label 'Control Vector(s)' -Type 'text' -Flag '--control-vector')
Add-OptionMeta (New-OptionMeta -Id 'control_vector_scaled' -Tab 'Performance' -Section 'Adapters and Control Vectors' -Label 'Scaled Control Vector(s)' -Type 'text' -Flag '--control-vector-scaled')
Add-OptionMeta (New-OptionMeta -Id 'control_vector_layer_range' -Tab 'Performance' -Section 'Adapters and Control Vectors' -Label 'Control Vector Layer Range' -Type 'text' -Flag '--control-vector-layer-range' -Arity 2)

Add-OptionMeta (New-OptionMeta -Id 'sampler_preset' -Tab 'Sampling' -Section 'Quick Setup' -Label 'Apply Sampler Preset' -Type 'preset' -Choices @('Choose preset...', 'Thinking - General', 'Thinking - Coding', 'Instruct - Balanced') -Default 'Choose preset...' -Basic $true -DisplayFlag 'Launcher: applies sampler values' -Kind 'Launcher')
Add-OptionMeta (New-OptionMeta -Id 'samplers' -Tab 'Sampling' -Section 'Sampler Order' -Label 'Samplers' -Type 'text' -Flag '--samplers')
Add-OptionMeta (New-OptionMeta -Id 'sampler_seq' -Tab 'Sampling' -Section 'Sampler Order' -Label 'Sampler Sequence' -Type 'text' -Flag '--sampler-seq')
Add-OptionMeta (New-OptionMeta -Id 'seed' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Seed' -Type 'number' -Flag '--seed' -Default -1 -Min -1 -Max 2147483647 -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'ignore_eos' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Ignore EOS' -Type 'flag' -Flag '--ignore-eos')
Add-OptionMeta (New-OptionMeta -Id 'temp' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Temperature' -Type 'decimal' -Flag '--temp' -Default 0.80 -Min 0.00 -Max 10.00 -Increment 0.05 -Decimals 2 -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'top_k' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Top-K' -Type 'number' -Flag '--top-k' -Default 40 -Min 0 -Max 100000 -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'top_p' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Top-P' -Type 'decimal' -Flag '--top-p' -Default 0.95 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2 -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'min_p' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Min-P' -Type 'decimal' -Flag '--min-p' -Default 0.05 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2 -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'top_n_sigma' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Top-N Sigma' -Type 'decimal' -Flag '--top-n-sigma' -Default -1.00 -Min -10.00 -Max 10.00 -Increment 0.05 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'xtc_probability' -Tab 'Sampling' -Section 'Core Sampling' -Label 'XTC Probability' -Type 'decimal' -Flag '--xtc-probability' -Default 0.00 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'xtc_threshold' -Tab 'Sampling' -Section 'Core Sampling' -Label 'XTC Threshold' -Type 'decimal' -Flag '--xtc-threshold' -Default 0.10 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'typical_p' -Tab 'Sampling' -Section 'Core Sampling' -Label 'Typical-P' -Type 'decimal' -Flag '--typical-p' -Default 1.00 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'repeat_last_n' -Tab 'Sampling' -Section 'Penalties' -Label 'Repeat Last N' -Type 'number' -Flag '--repeat-last-n' -Default 64 -Min -1 -Max 1048576)
Add-OptionMeta (New-OptionMeta -Id 'repeat_penalty' -Tab 'Sampling' -Section 'Penalties' -Label 'Repeat Penalty' -Type 'decimal' -Flag '--repeat-penalty' -Default 1.00 -Min 0.00 -Max 10.00 -Increment 0.01 -Decimals 2 -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'presence_penalty' -Tab 'Sampling' -Section 'Penalties' -Label 'Presence Penalty' -Type 'decimal' -Flag '--presence-penalty' -Default 0.00 -Min -5.00 -Max 5.00 -Increment 0.01 -Decimals 2 -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'frequency_penalty' -Tab 'Sampling' -Section 'Penalties' -Label 'Frequency Penalty' -Type 'decimal' -Flag '--frequency-penalty' -Default 0.00 -Min -5.00 -Max 5.00 -Increment 0.01 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'dry_multiplier' -Tab 'Sampling' -Section 'DRY and Adaptive' -Label 'DRY Multiplier' -Type 'decimal' -Flag '--dry-multiplier' -Default 0.00 -Min 0.00 -Max 10.00 -Increment 0.05 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'dry_base' -Tab 'Sampling' -Section 'DRY and Adaptive' -Label 'DRY Base' -Type 'decimal' -Flag '--dry-base' -Default 1.75 -Min 0.00 -Max 10.00 -Increment 0.05 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'dry_allowed_length' -Tab 'Sampling' -Section 'DRY and Adaptive' -Label 'DRY Allowed Length' -Type 'number' -Flag '--dry-allowed-length' -Default 2 -Min 0 -Max 100000)
Add-OptionMeta (New-OptionMeta -Id 'dry_penalty_last_n' -Tab 'Sampling' -Section 'DRY and Adaptive' -Label 'DRY Penalty Last N' -Type 'number' -Flag '--dry-penalty-last-n' -Default -1 -Min -1 -Max 1048576)
Add-OptionMeta (New-OptionMeta -Id 'dry_sequence_breaker' -Tab 'Sampling' -Section 'DRY and Adaptive' -Label 'DRY Sequence Breaker' -Type 'text' -Flag '--dry-sequence-breaker')
Add-OptionMeta (New-OptionMeta -Id 'adaptive_target' -Tab 'Sampling' -Section 'DRY and Adaptive' -Label 'Adaptive Target' -Type 'decimal' -Flag '--adaptive-target' -Default -1.00 -Min -1.00 -Max 1.00 -Increment 0.01 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'adaptive_decay' -Tab 'Sampling' -Section 'DRY and Adaptive' -Label 'Adaptive Decay' -Type 'decimal' -Flag '--adaptive-decay' -Default 0.90 -Min 0.00 -Max 0.99 -Increment 0.01 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'dynatemp_range' -Tab 'Sampling' -Section 'Dynamic Temperature and Mirostat' -Label 'Dynatemp Range' -Type 'decimal' -Flag '--dynatemp-range' -Default 0.00 -Min 0.00 -Max 10.00 -Increment 0.05 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'dynatemp_exp' -Tab 'Sampling' -Section 'Dynamic Temperature and Mirostat' -Label 'Dynatemp Exponent' -Type 'decimal' -Flag '--dynatemp-exp' -Default 1.00 -Min 0.00 -Max 10.00 -Increment 0.05 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'mirostat' -Tab 'Sampling' -Section 'Dynamic Temperature and Mirostat' -Label 'Mirostat Mode' -Type 'combo' -Flag '--mirostat' -Choices @('0', '1', '2') -Default '0')
Add-OptionMeta (New-OptionMeta -Id 'mirostat_lr' -Tab 'Sampling' -Section 'Dynamic Temperature and Mirostat' -Label 'Mirostat Learning Rate' -Type 'decimal' -Flag '--mirostat-lr' -Default 0.10 -Min 0.00 -Max 10.00 -Increment 0.01 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'mirostat_ent' -Tab 'Sampling' -Section 'Dynamic Temperature and Mirostat' -Label 'Mirostat Target Entropy' -Type 'decimal' -Flag '--mirostat-ent' -Default 5.00 -Min 0.00 -Max 20.00 -Increment 0.05 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'logit_bias' -Tab 'Sampling' -Section 'Constraints' -Label 'Logit Bias' -Type 'text' -Flag '--logit-bias')
Add-OptionMeta (New-OptionMeta -Id 'grammar' -Tab 'Sampling' -Section 'Constraints' -Label 'Grammar' -Type 'text' -Flag '--grammar')
Add-OptionMeta (New-OptionMeta -Id 'grammar_file' -Tab 'Sampling' -Section 'Constraints' -Label 'Grammar File' -Type 'path' -Flag '--grammar-file' -BrowseMode 'file' -Filter 'Grammar files (*.gbnf)|*.gbnf|All files (*.*)|*.*')
Add-OptionMeta (New-OptionMeta -Id 'json_schema' -Tab 'Sampling' -Section 'Constraints' -Label 'JSON Schema' -Type 'text' -Flag '--json-schema')
Add-OptionMeta (New-OptionMeta -Id 'json_schema_file' -Tab 'Sampling' -Section 'Constraints' -Label 'JSON Schema File' -Type 'path' -Flag '--json-schema-file' -BrowseMode 'file' -Filter 'JSON files (*.json)|*.json|All files (*.*)|*.*')
Add-OptionMeta (New-OptionMeta -Id 'backend_sampling' -Tab 'Sampling' -Section 'Constraints' -Label 'Backend Sampling' -Type 'flag' -Flag '--backend-sampling')

Add-OptionMeta (New-OptionMeta -Id 'reverse_prompt' -Tab 'Chat' -Section 'Prompt and Parsing' -Label 'Reverse Prompt' -Type 'text' -Flag '--reverse-prompt')
Add-OptionMeta (New-OptionMeta -Id 'special' -Tab 'Chat' -Section 'Prompt and Parsing' -Label 'Special Tokens Output' -Type 'flag' -Flag '--special')
Add-OptionMeta (New-OptionMeta -Id 'pooling' -Tab 'Chat' -Section 'Embeddings and Reranking' -Label 'Pooling' -Type 'combo' -Flag '--pooling' -Choices @('none', 'mean', 'cls', 'last', 'rank') -Default 'mean')
Add-OptionMeta (New-OptionMeta -Id 'embedding' -Tab 'Chat' -Section 'Embeddings and Reranking' -Label 'Embedding-only Mode' -Type 'flag' -Flag '--embedding')
Add-OptionMeta (New-OptionMeta -Id 'reranking' -Tab 'Chat' -Section 'Embeddings and Reranking' -Label 'Reranking Endpoint' -Type 'flag' -Flag '--reranking')
Add-OptionMeta (New-OptionMeta -Id 'jinja' -Tab 'Chat' -Section 'Chat Template / Reasoning' -Label 'Jinja Engine' -Type 'pair' -Flag '--jinja' -NegFlag '--no-jinja' -Default 'Enabled' -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'reasoning_format' -Tab 'Chat' -Section 'Chat Template / Reasoning' -Label 'Reasoning Format' -Type 'combo' -Flag '--reasoning-format' -Choices @('auto', 'none', 'deepseek', 'deepseek-legacy') -Default 'auto')
Add-OptionMeta (New-OptionMeta -Id 'reasoning' -Tab 'Chat' -Section 'Chat Template / Reasoning' -Label 'Reasoning / Thinking' -Type 'combo' -Flag '--reasoning' -Choices @('auto', 'on', 'off') -Default 'auto' -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'reasoning_budget' -Tab 'Chat' -Section 'Chat Template / Reasoning' -Label 'Reasoning Budget' -Type 'number' -Flag '--reasoning-budget' -Default -1 -Min -1 -Max 1000000 -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'reasoning_budget_message' -Tab 'Chat' -Section 'Chat Template / Reasoning' -Label 'Reasoning Budget Message' -Type 'text' -Flag '--reasoning-budget-message')
Add-OptionMeta (New-OptionMeta -Id 'chat_template' -Tab 'Chat' -Section 'Chat Template / Reasoning' -Label 'Chat Template' -Type 'combo' -Flag '--chat-template' -Choices $chatTemplates -Default 'chatml' -Editable $true -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'chat_template_file' -Tab 'Chat' -Section 'Chat Template / Reasoning' -Label 'Chat Template File' -Type 'path' -Flag '--chat-template-file' -BrowseMode 'file' -Filter 'Template files (*.jinja;*.txt)|*.jinja;*.txt|All files (*.*)|*.*')
Add-OptionMeta (New-OptionMeta -Id 'enable_thinking' -Tab 'Chat' -Section 'Chat Template / Reasoning' -Label 'Enable Thinking' -Type 'combo' -Flag '' -Choices @('Force on', 'Force off') -Default 'Force off' -Basic $true -DisplayFlag 'via --chat-template-kwargs' -Kind 'Generated')
Add-OptionMeta (New-OptionMeta -Id 'preserve_thinking' -Tab 'Chat' -Section 'Chat Template / Reasoning' -Label 'Preserve Reasoning History' -Type 'pair' -Flag '' -Default 'Enabled' -Basic $true -DisplayFlag 'via --chat-template-kwargs' -Kind 'Generated')
Add-OptionMeta (New-OptionMeta -Id 'chat_template_kwargs' -Tab 'Chat' -Section 'Chat Template / Reasoning' -Label 'Chat Template Kwargs JSON' -Type 'text' -Flag '--chat-template-kwargs')
Add-OptionMeta (New-OptionMeta -Id 'skip_chat_parsing' -Tab 'Chat' -Section 'Chat Template / Reasoning' -Label 'Skip Chat Parsing' -Type 'pair' -Flag '--skip-chat-parsing' -NegFlag '--no-skip-chat-parsing' -Default 'Disabled')
Add-OptionMeta (New-OptionMeta -Id 'prefill_assistant' -Tab 'Chat' -Section 'Chat Template / Reasoning' -Label 'Prefill Assistant' -Type 'pair' -Flag '--prefill-assistant' -NegFlag '--no-prefill-assistant' -Default 'Enabled')
Add-OptionMeta (New-OptionMeta -Id 'lora_init_without_apply' -Tab 'Chat' -Section 'Chat Template / Reasoning' -Label 'LoRA Init Without Apply' -Type 'flag' -Flag '--lora-init-without-apply')

Add-OptionMeta (New-OptionMeta -Id 'mmproj' -Tab 'Multimodal' -Section 'Projector and Vision' -Label 'Multimodal Projector' -Type 'path' -Flag '--mmproj' -BrowseMode 'file' -Filter 'GGUF files (*.gguf)|*.gguf|All files (*.*)|*.*' -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'mmproj_url' -Tab 'Multimodal' -Section 'Projector and Vision' -Label 'Projector URL' -Type 'text' -Flag '--mmproj-url')
Add-OptionMeta (New-OptionMeta -Id 'mmproj_auto' -Tab 'Multimodal' -Section 'Projector and Vision' -Label 'Projector Auto-Use' -Type 'pair' -Flag '--mmproj-auto' -NegFlag '--no-mmproj' -Default 'Enabled')
Add-OptionMeta (New-OptionMeta -Id 'mmproj_offload' -Tab 'Multimodal' -Section 'Projector and Vision' -Label 'Projector GPU Offload' -Type 'pair' -Flag '--mmproj-offload' -NegFlag '--no-mmproj-offload' -Default 'Enabled')
Add-OptionMeta (New-OptionMeta -Id 'image_min_tokens' -Tab 'Multimodal' -Section 'Projector and Vision' -Label 'Image Min Tokens' -Type 'number' -Flag '--image-min-tokens' -Default 0 -Min 0 -Max 1000000)
Add-OptionMeta (New-OptionMeta -Id 'image_max_tokens' -Tab 'Multimodal' -Section 'Projector and Vision' -Label 'Image Max Tokens' -Type 'number' -Flag '--image-max-tokens' -Default 0 -Min 0 -Max 1000000)
Add-OptionMeta (New-OptionMeta -Id 'model_vocoder' -Tab 'Multimodal' -Section 'Audio and Vocoder' -Label 'Vocoder Model' -Type 'path' -Flag '--model-vocoder' -BrowseMode 'file' -Filter 'GGUF files (*.gguf)|*.gguf|All files (*.*)|*.*')
Add-OptionMeta (New-OptionMeta -Id 'hf_repo_v' -Tab 'Multimodal' -Section 'Audio and Vocoder' -Label 'HF Repo (Vocoder)' -Type 'text' -Flag '--hf-repo-v')
Add-OptionMeta (New-OptionMeta -Id 'hf_file_v' -Tab 'Multimodal' -Section 'Audio and Vocoder' -Label 'HF File (Vocoder)' -Type 'text' -Flag '--hf-file-v')
Add-OptionMeta (New-OptionMeta -Id 'tts_use_guide_tokens' -Tab 'Multimodal' -Section 'Audio and Vocoder' -Label 'TTS Guide Tokens' -Type 'flag' -Flag '--tts-use-guide-tokens')

Add-OptionMeta (New-OptionMeta -Id 'lookup_cache_static' -Tab 'Speculative' -Section 'Lookup and Draft Cache' -Label 'Static Lookup Cache' -Type 'path' -Flag '--lookup-cache-static' -BrowseMode 'file' -Filter 'All files (*.*)|*.*')
Add-OptionMeta (New-OptionMeta -Id 'lookup_cache_dynamic' -Tab 'Speculative' -Section 'Lookup and Draft Cache' -Label 'Dynamic Lookup Cache' -Type 'path' -Flag '--lookup-cache-dynamic' -BrowseMode 'file' -Filter 'All files (*.*)|*.*')
Add-OptionMeta (New-OptionMeta -Id 'cache_type_k_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft Cache Type K' -Type 'combo' -Flag '--cache-type-k-draft' -Choices $cacheTypes -Default 'f16')
Add-OptionMeta (New-OptionMeta -Id 'cache_type_v_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft Cache Type V' -Type 'combo' -Flag '--cache-type-v-draft' -Choices $cacheTypes -Default 'f16')
Add-OptionMeta (New-OptionMeta -Id 'hf_repo_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'HF Repo (Draft)' -Type 'text' -Flag '--hf-repo-draft')
Add-OptionMeta (New-OptionMeta -Id 'override_tensor_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Override Tensor Buffer (Draft)' -Type 'text' -Flag '--override-tensor-draft')
Add-OptionMeta (New-OptionMeta -Id 'cpu_moe_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Keep All Draft MoE on CPU' -Type 'flag' -Flag '--cpu-moe-draft')
Add-OptionMeta (New-OptionMeta -Id 'n_cpu_moe_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft CPU MoE Layers' -Type 'number' -Flag '--n-cpu-moe-draft' -Default 0 -Min 0 -Max 10000)
Add-OptionMeta (New-OptionMeta -Id 'threads_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft Threads' -Type 'number' -Flag '--threads-draft' -Default -1 -Min -1 -Max 256)
Add-OptionMeta (New-OptionMeta -Id 'threads_batch_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft Batch Threads' -Type 'number' -Flag '--threads-batch-draft' -Default -1 -Min -1 -Max 256)
Add-OptionMeta (New-OptionMeta -Id 'cpu_mask_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft CPU Mask' -Type 'text' -Flag '--cpu-mask-draft')
Add-OptionMeta (New-OptionMeta -Id 'cpu_range_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft CPU Range' -Type 'text' -Flag '--cpu-range-draft')
Add-OptionMeta (New-OptionMeta -Id 'cpu_strict_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Strict Draft CPU Placement' -Type 'combo' -Flag '--cpu-strict-draft' -Choices @('0', '1') -Default '0')
Add-OptionMeta (New-OptionMeta -Id 'prio_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft Priority' -Type 'combo' -Flag '--prio-draft' -Choices @('0', '1', '2', '3') -Default '0')
Add-OptionMeta (New-OptionMeta -Id 'poll_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft Polling' -Type 'combo' -Flag '--poll-draft' -Choices @('0', '1') -Default '0')
Add-OptionMeta (New-OptionMeta -Id 'cpu_mask_batch_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft Batch CPU Mask' -Type 'text' -Flag '--cpu-mask-batch-draft')
Add-OptionMeta (New-OptionMeta -Id 'cpu_strict_batch_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Strict Draft Batch Placement' -Type 'combo' -Flag '--cpu-strict-batch-draft' -Choices @('0', '1') -Default '0')
Add-OptionMeta (New-OptionMeta -Id 'prio_batch_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft Batch Priority' -Type 'combo' -Flag '--prio-batch-draft' -Choices @('0', '1', '2', '3') -Default '0')
Add-OptionMeta (New-OptionMeta -Id 'poll_batch_draft' -Tab 'Speculative' -Section 'Draft Model' -Label 'Draft Batch Polling' -Type 'combo' -Flag '--poll-batch-draft' -Choices @('0', '1') -Default '0')
Add-OptionMeta (New-OptionMeta -Id 'draft_max' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Draft Tokens' -Type 'number' -Flag '--draft-max' -Default 16 -Min 0 -Max 100000)
Add-OptionMeta (New-OptionMeta -Id 'draft_min' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Draft Min Tokens' -Type 'number' -Flag '--draft-min' -Default 0 -Min 0 -Max 100000)
Add-OptionMeta (New-OptionMeta -Id 'draft_p_min' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Draft Min Probability' -Type 'decimal' -Flag '--draft-p-min' -Default 0.75 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'ctx_size_draft' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Draft Context Size' -Type 'number' -Flag '--ctx-size-draft' -Default 0 -Min 0 -Max 1048576)
Add-OptionMeta (New-OptionMeta -Id 'device_draft' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Draft Device(s)' -Type 'text' -Flag '--device-draft')
Add-OptionMeta (New-OptionMeta -Id 'n_gpu_layers_draft' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Draft GPU Layers' -Type 'combo' -Flag '--n-gpu-layers-draft' -Choices @('auto', 'all', '0', '16', '32', '64', '99', '999') -Default 'auto' -Editable $true)
Add-OptionMeta (New-OptionMeta -Id 'model_draft' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Draft Model' -Type 'path' -Flag '--model-draft' -BrowseMode 'file' -Filter 'GGUF files (*.gguf)|*.gguf|All files (*.*)|*.*')
Add-OptionMeta (New-OptionMeta -Id 'spec_replace' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Spec Replace' -Type 'text' -Flag '--spec-replace' -Arity 2)
Add-OptionMeta (New-OptionMeta -Id 'spec_type' -Tab 'Speculative' -Section 'Speculative Decoding' -Label 'Spec Type' -Type 'combo' -Flag '--spec-type' -Choices @('none', 'ngram-cache', 'ngram-simple', 'ngram-map-k', 'ngram-map-k4v', 'ngram-mod') -Default 'none')
Add-OptionMeta (New-OptionMeta -Id 'spec_ngram_size_n' -Tab 'Speculative' -Section 'N-gram Speculation' -Label 'N-gram Size N' -Type 'number' -Flag '--spec-ngram-size-n' -Default 12 -Min 1 -Max 1000)
Add-OptionMeta (New-OptionMeta -Id 'spec_ngram_size_m' -Tab 'Speculative' -Section 'N-gram Speculation' -Label 'N-gram Size M' -Type 'number' -Flag '--spec-ngram-size-m' -Default 48 -Min 1 -Max 1000)
Add-OptionMeta (New-OptionMeta -Id 'spec_ngram_min_hits' -Tab 'Speculative' -Section 'N-gram Speculation' -Label 'N-gram Min Hits' -Type 'number' -Flag '--spec-ngram-min-hits' -Default 1 -Min 1 -Max 100000)

Add-OptionMeta (New-OptionMeta -Id 'ctx_checkpoints' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Context Checkpoints' -Type 'number' -Flag '--ctx-checkpoints' -Default 32 -Min 0 -Max 100000)
Add-OptionMeta (New-OptionMeta -Id 'checkpoint_every_tokens' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Checkpoint Every N Tokens' -Type 'number' -Flag '--checkpoint-every-n-tokens' -Default 8192 -Min -1 -Max 1000000)
Add-OptionMeta (New-OptionMeta -Id 'cache_ram' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Cache RAM (MiB)' -Type 'number' -Flag '--cache-ram' -Default 8192 -Min -1 -Max 1048576)
Add-OptionMeta (New-OptionMeta -Id 'kv_unified' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Unified KV Buffer' -Type 'pair' -Flag '--kv-unified' -NegFlag '--no-kv-unified' -Default 'Enabled')
Add-OptionMeta (New-OptionMeta -Id 'cache_idle_slots' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Cache Idle Slots' -Type 'pair' -Flag '--cache-idle-slots' -NegFlag '--no-cache-idle-slots' -Default 'Enabled')
Add-OptionMeta (New-OptionMeta -Id 'context_shift' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Context Shift' -Type 'pair' -Flag '--context-shift' -NegFlag '--no-context-shift' -Default 'Disabled')
Add-OptionMeta (New-OptionMeta -Id 'warmup' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Warmup' -Type 'pair' -Flag '--warmup' -NegFlag '--no-warmup' -Default 'Enabled')
Add-OptionMeta (New-OptionMeta -Id 'spm_infill' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'SPM Infill Pattern' -Type 'flag' -Flag '--spm-infill')
Add-OptionMeta (New-OptionMeta -Id 'parallel' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Parallel Slots' -Type 'number' -Flag '--parallel' -Default -1 -Min -1 -Max 1024)
Add-OptionMeta (New-OptionMeta -Id 'cont_batching' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Continuous Batching' -Type 'pair' -Flag '--cont-batching' -NegFlag '--no-cont-batching' -Default 'Enabled')
Add-OptionMeta (New-OptionMeta -Id 'cache_prompt' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Prompt Cache' -Type 'pair' -Flag '--cache-prompt' -NegFlag '--no-cache-prompt' -Default 'Enabled')
Add-OptionMeta (New-OptionMeta -Id 'cache_reuse' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Cache Reuse Chunk Size' -Type 'number' -Flag '--cache-reuse' -Default 0 -Min 0 -Max 1000000)
Add-OptionMeta (New-OptionMeta -Id 'slot_prompt_similarity' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Slot Prompt Similarity' -Type 'decimal' -Flag '--slot-prompt-similarity' -Default 0.10 -Min 0.00 -Max 1.00 -Increment 0.01 -Decimals 2)
Add-OptionMeta (New-OptionMeta -Id 'sleep_idle_seconds' -Tab 'Router' -Section 'Server Batching and Cache' -Label 'Sleep Idle Seconds' -Type 'number' -Flag '--sleep-idle-seconds' -Default -1 -Min -1 -Max 86400)
Add-OptionMeta (New-OptionMeta -Id 'models_dir' -Tab 'Router' -Section 'Router Mode' -Label 'Models Directory' -Type 'folder' -Flag '--models-dir' -BrowseMode 'folder' -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'models_preset' -Tab 'Router' -Section 'Router Mode' -Label 'Models Preset File' -Type 'path' -Flag '--models-preset' -BrowseMode 'file' -Filter 'INI files (*.ini)|*.ini|All files (*.*)|*.*' -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'models_max' -Tab 'Router' -Section 'Router Mode' -Label 'Max Loaded Models' -Type 'number' -Flag '--models-max' -Default 4 -Min 0 -Max 1024 -Basic $true)
Add-OptionMeta (New-OptionMeta -Id 'models_autoload' -Tab 'Router' -Section 'Router Mode' -Label 'Router Autoload' -Type 'pair' -Flag '--models-autoload' -NegFlag '--no-models-autoload' -Default 'Enabled' -Basic $true)

Add-OptionMeta (New-OptionMeta -Id 'log_disable' -Tab 'Logging' -Section 'Logging' -Label 'Disable Logging' -Type 'flag' -Flag '--log-disable')
Add-OptionMeta (New-OptionMeta -Id 'log_file' -Tab 'Logging' -Section 'Logging' -Label 'Log File' -Type 'path' -Flag '--log-file' -BrowseMode 'file' -Filter 'Log files (*.log;*.txt)|*.log;*.txt|All files (*.*)|*.*')
Add-OptionMeta (New-OptionMeta -Id 'log_colors' -Tab 'Logging' -Section 'Logging' -Label 'Log Colors' -Type 'combo' -Flag '--log-colors' -Choices @('auto', 'on', 'off') -Default 'auto')
Add-OptionMeta (New-OptionMeta -Id 'verbose' -Tab 'Logging' -Section 'Logging' -Label 'Verbose Logging' -Type 'flag' -Flag '--verbose')
Add-OptionMeta (New-OptionMeta -Id 'verbosity' -Tab 'Logging' -Section 'Logging' -Label 'Verbosity Threshold' -Type 'combo' -Flag '--verbosity' -Choices @('0', '1', '2', '3', '4') -Default '3')
Add-OptionMeta (New-OptionMeta -Id 'log_prefix' -Tab 'Logging' -Section 'Logging' -Label 'Log Prefix' -Type 'flag' -Flag '--log-prefix')
Add-OptionMeta (New-OptionMeta -Id 'log_timestamps' -Tab 'Logging' -Section 'Logging' -Label 'Log Timestamps' -Type 'flag' -Flag '--log-timestamps')

$form = New-Object System.Windows.Forms.Form
$form.Text = 'llama-server-launcher'
$screenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$idealW = 1280
$idealH = 880
$startW = [Math]::Min($idealW, [Math]::Max(1100, $screenBounds.Width - 80))
$startH = [Math]::Min($idealH, [Math]::Max(720, $screenBounds.Height - 80))
$form.Size = [System.Drawing.Size]::new($startW, $startH)
$form.MinimumSize = [System.Drawing.Size]::new(1100, 720)
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
$subtitleLabel.Text = 'Quick Setup shows the settings most people actually touch. All Options keeps the complete llama-server surface. Unchecked rows stay gray and are omitted from the live command.'
$subtitleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$subtitleLabel.ForeColor = [System.Drawing.Color]::Gray
$subtitleLabel.Location = [System.Drawing.Point]::new(15, 40)
$subtitleLabel.Size = [System.Drawing.Size]::new(1320, 18)
$subtitleLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($subtitleLabel)
$script:subtitleLabel = $subtitleLabel

$grpRequired = New-Object System.Windows.Forms.GroupBox
$grpRequired.Text = 'Launch Setup'
$grpRequired.Location = [System.Drawing.Point]::new(10, 62)
$grpRequired.Size = [System.Drawing.Size]::new(1340, 88)
$grpRequired.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$grpRequired.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($grpRequired)
$script:grpRequired = $grpRequired

$lblServer = New-Object System.Windows.Forms.Label
$lblServer.Text = 'llama-server.exe'
$lblServer.Location = [System.Drawing.Point]::new(12, 29)
$lblServer.Size = [System.Drawing.Size]::new(128, 20)
$lblServer.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$grpRequired.Controls.Add($lblServer)
$script:lblServerRequired = $lblServer

$txtServer = New-Object System.Windows.Forms.TextBox
$txtServer.Location = [System.Drawing.Point]::new(150, 26)
$txtServer.Size = [System.Drawing.Size]::new(1070, 24)
$txtServer.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$txtServer.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtServer.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$grpRequired.Controls.Add($txtServer)
$script:txtServer = $txtServer

$btnServer = New-Object System.Windows.Forms.Button
$btnServer.Text = 'Browse'
$btnServer.Location = [System.Drawing.Point]::new(1228, 25)
$btnServer.Size = [System.Drawing.Size]::new(92, 27)
$btnServer.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$btnServer.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$btnServer.Add_Click({
    $selected = & ${function:Browse-Path} -Title 'Select llama-server.exe' -Mode 'file' -Filter 'llama-server.exe (recommended)|llama-server.exe|Executable files (*.exe)|*.exe|All files (*.*)|*.*' -StartDir $script:BatDir
    if ($selected) {
        $script:txtServer.Text = $selected
    }
}.GetNewClosure())
$grpRequired.Controls.Add($btnServer)
$script:btnServer = $btnServer

$lblModel = New-Object System.Windows.Forms.Label
$lblModel.Text = 'Model (.gguf)'
$lblModel.Location = [System.Drawing.Point]::new(12, 58)
$lblModel.Size = [System.Drawing.Size]::new(128, 20)
$lblModel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$grpRequired.Controls.Add($lblModel)
$script:lblModel = $lblModel

$txtModel = New-Object System.Windows.Forms.TextBox
$txtModel.Location = [System.Drawing.Point]::new(150, 55)
$txtModel.Size = [System.Drawing.Size]::new(1070, 24)
$txtModel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$txtModel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtModel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$grpRequired.Controls.Add($txtModel)
$script:txtModel = $txtModel

$btnModel = New-Object System.Windows.Forms.Button
$btnModel.Text = 'Browse'
$btnModel.Location = [System.Drawing.Point]::new(1228, 54)
$btnModel.Size = [System.Drawing.Size]::new(92, 27)
$btnModel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$btnModel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$btnModel.Add_Click({
    $startDir = if ($script:txtModel.Text -and (Test-Path -LiteralPath $script:txtModel.Text)) { Split-Path -Parent $script:txtModel.Text } else { $script:BatDir }
    $selected = & ${function:Browse-Path} -Title 'Select GGUF Model' -Mode 'file' -Filter 'GGUF files (*.gguf)|*.gguf|All files (*.*)|*.*' -StartDir $startDir
    if ($selected) {
        $script:txtModel.Text = $selected
    }
}.GetNewClosure())
$grpRequired.Controls.Add($btnModel)
$script:btnModel = $btnModel

& ${function:Register-HelpText} -Control $lblServer -Title 'llama-server.exe' -Text 'Choose your llama-server.exe. If this launcher sits next to llama-server.exe, it will usually auto-fill.'
& ${function:Register-HelpText} -Control $lblModel -Title 'Model (.gguf)' -Text 'Optional. If this field has a path, the launcher adds --model. Leave it blank for router sources, remote sources, cache use, or utility commands.'

$mainSplit = New-Object System.Windows.Forms.SplitContainer
$mainSplit.Orientation = [System.Windows.Forms.Orientation]::Horizontal
$mainSplit.Location = [System.Drawing.Point]::new(10, 160)
$mainSplit.Size = [System.Drawing.Size]::new(1340, 735)
$mainSplit.SplitterWidth = 8
$mainSplit.Panel1MinSize = 300
$mainSplit.Panel2MinSize = 210
$mainSplit.SplitterDistance = 470
$mainSplit.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($mainSplit)
$script:mainSplit = $mainSplit

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabs.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$tabs.Add_SelectedIndexChanged({
    & ${function:Update-PreviewPanelLayout}
    if ($script:SuppressMainTabEvents) { return }

    $newTabKey = if ($script:MainTabs -and $script:MainTabs.SelectedTab) { [string]$script:MainTabs.SelectedTab.Tag } else { '' }
    if ($script:LastMainTabKey -eq 'AllOptions' -and $newTabKey -ne 'AllOptions') {
        & ${function:Restore-AllOptionsEditorSelection}
        & ${function:Update-MainTabs}
        return
    }

    if ($script:MainTabs -and $script:MainTabs.SelectedTab -and $script:MainTabs.SelectedTab.Tag -eq 'AllOptions') {
        & ${function:Update-AllOptionsPageLayout}
        & ${function:Refresh-AllOptionsList}
        if ($script:AllOptionsSearch) {
            [void]$script:AllOptionsSearch.Focus()
        }
    }
    $script:LastMainTabKey = $newTabKey
}.GetNewClosure())
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
        Y = 10
    }
}

$quickSetupPage = $script:TabPages['QuickSetup']
if ($quickSetupPage) {
    foreach ($group in $script:BasicLayout) {
        $sectionLabel = New-Object System.Windows.Forms.Label
        $sectionLabel.Text = $group.Section
        $sectionLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
        $sectionLabel.ForeColor = [System.Drawing.Color]::FromArgb(95, 95, 95)
        $sectionLabel.Size = [System.Drawing.Size]::new(900, 18)
        $sectionLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
        $sectionLabel.Visible = $false
        $quickSetupPage.Controls.Add($sectionLabel)
        [void]$script:QuickSetupSectionLabels.Add([PSCustomObject]@{
            Section = $group.Section
            Control = $sectionLabel
        })
    }
}

$allOptionsPage = $script:TabPages['AllOptions']
$allOptionsPage.AutoScroll = $false
$script:AllOptionsPage = $allOptionsPage
$searchLabel = New-Object System.Windows.Forms.Label
$searchLabel.Text = 'Search every setting. Select one to edit it here.'
$searchLabel.Location = [System.Drawing.Point]::new(12, 10)
$searchLabel.Size = [System.Drawing.Size]::new(900, 18)
$searchLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$searchLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$searchLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$allOptionsPage.Controls.Add($searchLabel)
$script:AllOptionsSearchLabel = $searchLabel

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Location = [System.Drawing.Point]::new(12, 32)
$searchBox.Size = [System.Drawing.Size]::new(360, 26)
$searchBox.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$searchBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$allOptionsPage.Controls.Add($searchBox)
$script:AllOptionsSearch = $searchBox

$btnRefreshAllOptions = New-Object System.Windows.Forms.Button
$btnRefreshAllOptions.Text = 'Clear'
$btnRefreshAllOptions.Location = [System.Drawing.Point]::new(378, 32)
$btnRefreshAllOptions.Size = [System.Drawing.Size]::new(58, 26)
$btnRefreshAllOptions.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$btnRefreshAllOptions.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRefreshAllOptions.FlatAppearance.BorderSize = 1
$btnRefreshAllOptions.BackColor = [System.Drawing.Color]::White
$btnRefreshAllOptions.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnRefreshAllOptions.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$btnRefreshAllOptions.Add_Click({
    & ${function:Clear-AllOptionsSearch}
}.GetNewClosure())
$allOptionsPage.Controls.Add($btnRefreshAllOptions)
$script:btnRefreshAllOptions = $btnRefreshAllOptions
$script:AllOptionsClearButton = $btnRefreshAllOptions

$script:AllOptionsFilter = 'All'

$filterPanel = New-Object System.Windows.Forms.Panel
$filterPanel.Location = [System.Drawing.Point]::new(450, 30)
$filterPanel.Size = [System.Drawing.Size]::new(360, 30)
$filterPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$allOptionsPage.Controls.Add($filterPanel)
$script:AllOptionsFilterPanel = $filterPanel

$filterLabel = New-Object System.Windows.Forms.Label
$filterLabel.Text = 'Show:'
$filterLabel.Location = [System.Drawing.Point]::new(0, 6)
$filterLabel.Size = [System.Drawing.Size]::new(40, 20)
$filterLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$filterLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$filterPanel.Controls.Add($filterLabel)

$script:AllOptionsFilterButtons = New-Object System.Collections.Generic.List[object]
$filterX = 42
foreach ($filter in @('All', 'Active', 'Basic')) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $filter
    $btn.Tag = $filter
    $btn.Location = [System.Drawing.Point]::new($filterX, 2)
    $btn.Size = [System.Drawing.Size]::new(88, 26)
    $btn.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 1
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Add_Click({
        param($sender, $eventArgs)
        $filterName = if ($sender -and $sender.Tag) { [string]$sender.Tag } else { 'All' }
        & ${function:Set-AllOptionsFilter} -Filter $filterName
    })
    $filterPanel.Controls.Add($btn)
    [void]$script:AllOptionsFilterButtons.Add($btn)
    $filterX += 96
}
& ${function:Update-AllOptionsFilterButtons}

$resultCountLabel = New-Object System.Windows.Forms.Label
$resultCountLabel.Location = [System.Drawing.Point]::new(992, 36)
$resultCountLabel.Size = [System.Drawing.Size]::new(280, 20)
$resultCountLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$resultCountLabel.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
$resultCountLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$resultCountLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$allOptionsPage.Controls.Add($resultCountLabel)
$script:AllOptionsCountLabel = $resultCountLabel

$allOptionsList = New-Object System.Windows.Forms.ListView
$allOptionsList.Location = [System.Drawing.Point]::new(12, 70)
$allOptionsList.Size = [System.Drawing.Size]::new(540, 416)
$allOptionsList.View = [System.Windows.Forms.View]::Details
$allOptionsList.FullRowSelect = $true
$allOptionsList.GridLines = $false
$allOptionsList.MultiSelect = $false
$allOptionsList.HideSelection = $false
$allOptionsList.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
$allOptionsList.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$allOptionsList.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
[void]$allOptionsList.Columns.Add('', 24)
[void]$allOptionsList.Columns.Add('Setting', 220)
[void]$allOptionsList.Columns.Add('Command / Effect', 276)
$allOptionsList.Add_SizeChanged({
    & ${function:Update-AllOptionsListColumns}
}.GetNewClosure())
$allOptionsPage.Controls.Add($allOptionsList)
$script:AllOptionsList = $allOptionsList

$emptyStateLabel = New-Object System.Windows.Forms.Label
$emptyStateLabel.Text = 'No settings match your search.'
$emptyStateLabel.Location = [System.Drawing.Point]::new(24, 110)
$emptyStateLabel.Size = [System.Drawing.Size]::new(500, 48)
$emptyStateLabel.Font = New-Object System.Drawing.Font('Segoe UI', 11)
$emptyStateLabel.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 150)
$emptyStateLabel.Visible = $false
$emptyStateLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$emptyStateLabel.BringToFront()
$allOptionsPage.Controls.Add($emptyStateLabel)
$script:AllOptionsEmptyState = $emptyStateLabel

$editorPanel = New-Object System.Windows.Forms.Panel
$editorPanel.Location = [System.Drawing.Point]::new(568, 70)
$editorPanel.Size = [System.Drawing.Size]::new(704, 416)
$editorPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$editorPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$editorPanel.BackColor = [System.Drawing.Color]::White
$editorPanel.AutoScroll = $true
$allOptionsPage.Controls.Add($editorPanel)
$script:AllOptionsEditorPanel = $editorPanel

$editorEmpty = New-Object System.Windows.Forms.Label
$editorEmpty.Text = 'Select an option to edit.'
$editorEmpty.Location = [System.Drawing.Point]::new(16, 14)
$editorEmpty.Size = [System.Drawing.Size]::new(640, 28)
$editorEmpty.Font = New-Object System.Drawing.Font('Segoe UI', 11)
$editorEmpty.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
$editorPanel.Controls.Add($editorEmpty)
$script:AllOptionsEditorEmpty = $editorEmpty

$editorTitle = New-Object System.Windows.Forms.Label
$editorTitle.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$editorTitle.ForeColor = [System.Drawing.Color]::FromArgb(35, 35, 35)
$editorTitle.AutoEllipsis = $true
$editorTitle.Visible = $false
$editorPanel.Controls.Add($editorTitle)
$script:AllOptionsEditorTitle = $editorTitle

$editorMeta = New-Object System.Windows.Forms.Label
$editorMeta.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$editorMeta.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
$editorMeta.AutoEllipsis = $true
$editorMeta.Visible = $false
$editorPanel.Controls.Add($editorMeta)
$script:AllOptionsEditorMeta = $editorMeta

$editorFlag = New-Object System.Windows.Forms.Label
$editorFlag.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$editorFlag.ForeColor = [System.Drawing.Color]::FromArgb(75, 75, 75)
$editorFlag.AutoEllipsis = $true
$editorFlag.Visible = $false
$editorPanel.Controls.Add($editorFlag)
$script:AllOptionsEditorFlag = $editorFlag

$useLabel = New-Object System.Windows.Forms.Label
$useLabel.Text = 'Use in command'
$useLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$useLabel.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$useLabel.Visible = $false
$useLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
$useLabel.Add_Click({
    & ${function:Toggle-AllOptionsSelectedUse}
})
$editorPanel.Controls.Add($useLabel)
$script:AllOptionsUseLabel = $useLabel

$valueLabel = New-Object System.Windows.Forms.Label
$valueLabel.Text = 'Value'
$valueLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
$valueLabel.ForeColor = [System.Drawing.Color]::FromArgb(95, 95, 95)
$valueLabel.Visible = $false
$editorPanel.Controls.Add($valueLabel)
$script:AllOptionsValueLabel = $valueLabel

$helpLabel = New-Object System.Windows.Forms.Label
$helpLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$helpLabel.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 90)
$helpLabel.Visible = $false
$helpLabel.AutoSize = $false
$helpLabel.UseMnemonic = $false
$editorPanel.Controls.Add($helpLabel)
$script:AllOptionsHelpLabel = $helpLabel
$editorPanel.Add_SizeChanged({
    & ${function:Update-AllOptionsEditorLayout}
}.GetNewClosure())

$script:AllOptionsSearchTimer = New-Object System.Windows.Forms.Timer
$script:AllOptionsSearchTimer.Interval = 150
$script:AllOptionsSearchTimer.Add_Tick({
    param($sender, $eventArgs)
    if ($sender) { $sender.Stop() }
    & ${function:Refresh-AllOptionsList}
}.GetNewClosure())
$searchBox.Add_TextChanged({
    if ($script:AllOptionsSearchTimer) {
        $script:AllOptionsSearchTimer.Stop()
        $script:AllOptionsSearchTimer.Start()
    }
}.GetNewClosure())
$allOptionsList.Add_SelectedIndexChanged({
    if ($script:AllOptionsRefreshing) { return }
    if ($script:AllOptionsList.SelectedItems.Count -lt 1) { return }
    $selected = $null
    foreach ($candidate in $script:AllOptionsList.SelectedItems) {
        $selected = $candidate
        break
    }
    if ($selected -and $selected.Tag) {
        & ${function:Show-AllOptionsEditor} -State $selected.Tag
    }
}.GetNewClosure())
& ${function:Update-AllOptionsPageLayout}

foreach ($page in $script:TabPages.Values) {
    if ($page) { $page.SuspendLayout() }
}
try {
    foreach ($option in $script:OptionCatalog) {
        Add-OptionRow -Option $option
    }
} finally {
    foreach ($page in $script:TabPages.Values) {
        if ($page) { $page.ResumeLayout($false) }
    }
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
$txtPreview.Size = [System.Drawing.Size]::new(1318, 156)
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

$script:CopyResetTimer = New-Object System.Windows.Forms.Timer
$script:CopyResetTimer.Interval = 1500
$script:CopyResetTimer.Add_Tick({
    $script:CopyResetTimer.Stop()
    if ($script:btnCopy -and -not $script:btnCopy.IsDisposed) {
        $script:btnCopy.Text = 'Copy Command'
    }
}.GetNewClosure())

$btnCopy.Add_Click({
    [System.Windows.Forms.Clipboard]::SetText((& ${function:Get-FlatCommandText}))
    $script:btnCopy.Text = 'Copied!'
    $script:CopyResetTimer.Stop()
    $script:CopyResetTimer.Start()
}.GetNewClosure())
$mainSplit.Panel2.Controls.Add($btnCopy)
$script:btnCopy = $btnCopy

$btnSaveCmd = New-Object System.Windows.Forms.Button
$btnSaveCmd.Text = 'Save Command'
$btnSaveCmd.Location = [System.Drawing.Point]::new(143, 172)
$btnSaveCmd.Size = [System.Drawing.Size]::new(135, 32)
$btnSaveCmd.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$btnSaveCmd.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnSaveCmd.Add_Click({
    if (-not (& ${function:Test-LaunchValid})) { return }

    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    try {
        $sfd.Title = 'Save launcher command'
        $sfd.Filter = 'Batch files (*.bat)|*.bat|Command files (*.cmd)|*.cmd|All files (*.*)|*.*'
        $sfd.DefaultExt = 'bat'
        $sfd.AddExtension = $true
        $sfd.FileName = 'run-llama-server.bat'
        if ($script:BatDir -and (Test-Path -LiteralPath $script:BatDir)) {
            $sfd.InitialDirectory = $script:BatDir
        }

        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        $content = & ${function:Build-SavedCommandText}
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($sfd.FileName, $content, $utf8NoBom)
        [System.Windows.Forms.MessageBox]::Show(
            ('Saved to: ' + $sfd.FileName + "`r`n`r`nDouble-click that file to relaunch with the same options."),
            'Save Command',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            ('Could not save the file: ' + $_.Exception.Message),
            'Save Command Failed',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    } finally {
        $sfd.Dispose()
    }
}.GetNewClosure())
$mainSplit.Panel2.Controls.Add($btnSaveCmd)
$script:btnSaveCmd = $btnSaveCmd

$btnReset = New-Object System.Windows.Forms.Button
$btnReset.Text = 'Reset All Overrides'
$btnReset.Location = [System.Drawing.Point]::new(286, 172)
$btnReset.Size = [System.Drawing.Size]::new(160, 32)
$btnReset.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$btnReset.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnReset.Add_Click({
    & ${function:Reset-AllOverrides}
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

& ${function:Register-HelpText} -Control $btnCopy -Title 'Copy command' -Text 'Copy the live command as one properly quoted line.'
& ${function:Register-HelpText} -Control $btnSaveCmd -Title 'Save command' -Text 'Save the live command as a reusable .bat file.'
& ${function:Register-HelpText} -Control $btnReset -Title 'Reset overrides' -Text 'Uncheck every override and reset option values to llama-server defaults. Server and model are kept.'
& ${function:Register-HelpText} -Control $btnLaunch -Title 'Run llama-server' -Text 'Start llama-server with the live command and close this launcher.'

$txtServer.Add_TextChanged({ & ${function:Refresh-Preview} }.GetNewClosure())
$txtModel.Add_TextChanged({ & ${function:Refresh-Preview} }.GetNewClosure())
$form.Add_Shown({ & ${function:Update-WindowLayout} -ForceColumns }.GetNewClosure())
$form.Add_SizeChanged({ & ${function:Request-WindowLayout} }.GetNewClosure())
$mainSplit.Add_SplitterMoved({ & ${function:Update-PreviewPanelLayout} }.GetNewClosure())
$form.Add_FormClosed({
    foreach ($timer in @($script:LayoutTimer, $script:AllOptionsSearchTimer, $script:CopyResetTimer)) {
        if ($timer) {
            $timer.Stop()
            $timer.Dispose()
        }
    }
    $script:LayoutTimer = $null
    $script:AllOptionsSearchTimer = $null
    $script:CopyResetTimer = $null
    $script:HoverHelpLabel = $null
}.GetNewClosure())

Enable-DoubleBuffer $form
Enable-DoubleBuffer $mainSplit
Enable-DoubleBuffer $mainSplit.Panel1
Enable-DoubleBuffer $mainSplit.Panel2
Enable-DoubleBuffer $tabs
Enable-DoubleBuffer $allOptionsList
foreach ($page in $script:TabPages.Values) {
    Enable-DoubleBuffer $page
}
Disable-LabelMnemonics $form

foreach ($dir in @($script:BatDir, (Get-Location).Path) | Where-Object { $_ } | Select-Object -Unique) {
    $candidate = Join-Path $dir 'llama-server.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $txtServer.Text = $candidate
        break
    }
}

$btnLaunch.Add_Click({
    if (-not (& ${function:Test-LaunchValid})) { return }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:txtServer.Text
    $psi.Arguments = (((& ${function:Get-ArgumentTokens}) | ForEach-Object { & ${function:Quote-WindowsArgument} $_ }) -join ' ')
    $toolDir = & ${function:Get-ToolWorkingDir}
    if (-not [string]::IsNullOrWhiteSpace($toolDir)) {
        $psi.WorkingDirectory = $toolDir
    }
    $psi.UseShellExecute = $true
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    $form.Close()
})

Update-MainTabs
if (& ${function:Get-IsAllOptionsSelected}) {
    Refresh-AllOptionsList
}
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
