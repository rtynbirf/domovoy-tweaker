function Show-Domovoy {
    <#
    .SYNOPSIS
    Opens the Domovoy GUI: a thin WinForms client over the CLI (v0.7.0,
    production ergonomics pass in v1.6.0).

    .DESCRIPTION
    Every action the GUI can perform is one exact CLI command: the button
    first prints the command line ("CLI: Invoke-DomovoyFeature -Id ...") and
    then runs that very line, compiled into a scriptblock. No logic is
    duplicated - snapshots, dry-runs, elevation checks, verification probes
    and journal events all happen inside the same public commands you would
    call by hand. If the GUI disappeared tomorrow, everything it does would
    still be one command away.

    v1.6.0 production ergonomics:

    - Every CLI action runs in a background PowerShell runspace (a fresh
      session that imports the module itself), so the window NEVER freezes
      into "(Not responding)" while a feature applies. Output travels back
      through a synchronized queue drained by a UI timer; a Stop button
      cancels the running pipeline.
    - A global exception guard (Application.ThreadException in
      CatchException mode) replaces the JIT crash dialog: any unhandled
      UI-thread error becomes a readable dialog with a "copy details"
      option and a technical log under %LOCALAPPDATA%\Domovoy\logs.
    - A status bar shows the running command, the elevation state and the
      version; a non-admin session gets a one-click "Restart as
      administrator" (UAC) instead of cryptic access-denied output.
    - The catalog is searchable: the filter box narrows the feature list by
      id/title/risk as you type.
    - The window carries the product icon, enables visual styles and
      requests DPI awareness (crisp on scaled displays).

    The window shows the feature catalog with the journal status of every
    feature, buttons for the per-feature contour (dry-run / apply / undo /
    effect report) and a toolbar for the machine-wide contours (drift scan,
    change report, network report, auto-heal, theme switch, policy export,
    language switch). Every user-facing sentence comes from the strings
    table (Get-DomovoyStrings, v1.6 item 6): the window builds in the
    active language, the Language toolbar button switches en/ru for the
    session and writes the preference.

    Closure discipline (the v1.5.4 lesson, machine-pinned): every handler
    and delegate is bound with .GetNewClosure(), which snapshots only the
    function-local variables that ALREADY EXIST at the definition point.
    Therefore this file is written in strict dependency order, and
    late-built controls (the full button set, the stop button, the fill
    routine) are reached through the $state hashtable - a reference that is
    captured early and read late. The private string table is reached only
    through the module-bound bridge $stringsLive.

    .PARAMETER Preview
    Builds the whole window, wires every handler, appends the welcome text
    and returns the Form object without showing it. Used by the tests (and
    handy for smoke checks); the caller owns disposal. The Tag carries the
    live test surface: List, Output, Status, Search, Drain (one manual
    queue drain - the UI timer is not started in preview), State, Buttons,
    Handlers and the v1.5.4 closure Probe.

    .EXAMPLE
    Show-Domovoy

    .EXAMPLE
    $form = Show-Domovoy -Preview
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch]$Preview
    )

    if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
        throw 'Show-Domovoy requires Windows (WinForms).'
    }
    if (-not ('System.Windows.Forms.Form' -as [type])) {
        Add-Type -AssemblyName System.Windows.Forms
    }
    if (-not ('System.Drawing.Font' -as [type])) {
        Add-Type -AssemblyName System.Drawing
    }

    # v1.6 (item 6): every user-facing sentence comes from the strings
    # table. Labels freeze at build time (the languageSwitched message
    # asks the user to reopen); dynamic messages resolve live.
    $s = Get-DomovoyStrings

    # v1.5.4: every click handler below is bound with .GetNewClosure() - a
    # fresh dynamic module whose command lookup reaches only the GLOBAL
    # session state. Public commands resolve there (the shims import the
    # module -Global), but the PRIVATE string table does not: since the
    # localization wave every single click died with "Get-DomovoyStrings is
    # not recognized" - the exact portable-exe crash (Button.OnMouseUp ->
    # ScriptBlock.InvokeAsDelegateHelper -> CommandNotFoundException,
    # Windows PowerShell 5.1). This bridge scriptblock is created in module
    # scope, so the private function resolves inside its own bound session
    # state; the closures capture it as a plain variable and invoke it
    # with &. Machine-proven by the closure proof harness and by the click
    # regression test in Domovoy.V07.Tests.ps1, which fails on the pre-fix
    # code.
    $stringsLive = { Get-DomovoyStrings }

    # ---- v1.6.0 process-level presentation guards ---------------------------

    # Themed controls instead of the classic Win95 defaults.
    try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch { }

    # DPI awareness before any window exists: the Windows PowerShell 5.1
    # host is not DPI-aware by itself, so a scaled display renders the GUI
    # bitmap-stretched. System-aware is the safe level for 5.1.
    if (-not ('Domovoy.Native.Dpi' -as [type])) {
        try {
            Add-Type -Namespace Domovoy.Native -Name Dpi -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
'@
        } catch { }
    }
    try { if ('Domovoy.Native.Dpi' -as [type]) { [void][Domovoy.Native.Dpi]::SetProcessDPIAware() } } catch { }

    # The technical log: every unhandled UI-thread error lands here before
    # the dialog is shown, so a user report is always attachable to evidence.
    $logDir = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'Domovoy\logs'
    $logFile = Join-Path $logDir ('domovoy-gui-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))

    # Delegates fire OUTSIDE the function scope: they resolve only module-
    # scope ($script:) and their own locals. The shared bits go to module
    # scope once; repeated Show-Domovoy calls must not stack handlers.
    $script:GuiStringsBridge = $stringsLive
    $script:GuiLogFile = $logFile
    if (-not $script:GuiHandlersInstalled) {
        $script:GuiHandlersInstalled = $true

        $script:GuiAppendLog = {
            param([string]$Kind, [string]$Detail)
            try {
                $null = New-Item -Path (Split-Path -Parent $script:GuiLogFile) -ItemType Directory -Force
                $stamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                [System.IO.File]::AppendAllText(
                    $script:GuiLogFile,
                    "[$stamp][$Kind] $Detail" + [Environment]::NewLine,
                    [System.Text.Encoding]::UTF8)
            } catch { }
        }

        # UI-thread unhandled exceptions: readable dialog + log, never the
        # JIT/debugger surface the portable-exe crash produced.
        $uiHandler = [System.Threading.ThreadExceptionEventHandler] {
            param($sender, $e)
            $detail = $e.Exception.ToString()
            & $script:GuiAppendLog 'UIThread' $detail
            $sLive = & $script:GuiStringsBridge
            $message = $sLive.fatalErrorBody -f $e.Exception.Message, $script:GuiLogFile
            $answer = [System.Windows.Forms.MessageBox]::Show(
                $message, $sLive.fatalErrorTitle,
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Error)
            if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
                try { [System.Windows.Forms.Clipboard]::SetText($detail) } catch { }
            }
        }
        try { [System.Windows.Forms.Application]::add_ThreadException($uiHandler) } catch { }

        # Non-UI threads (the async worker) surface through AppDomain.
        $domainHandler = [System.UnhandledExceptionEventHandler] {
            param($sender, $e)
            $ex = $e.ExceptionObject -as [System.Exception]
            if ($ex) { & $script:GuiAppendLog 'Domain' $ex.ToString() }
        }
        try { [System.AppDomain]::CurrentDomain.add_UnhandledException($domainHandler) } catch { }
    }

    # ---- shared runtime state (defined before every closure) ----------------

    # The hashtable is a reference: closures capture it early and read its
    # members late, so controls built after the closures are reachable.
    # $uiQueue is the synchronized output bridge from the worker runspace.
    $uiQueue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    $state = @{
        busy          = $false
        cancelled     = $false
        hadOutput     = $false
        worker        = $null
        handle        = $null
        postAction    = $null
        features      = @()
        journal       = @{}
        fillList      = $null
        actionButtons = @()
        stopButton    = $null
    }

    # ---- controls -----------------------------------------------------------

    $module = Get-Module -Name Domovoy
    $form = [System.Windows.Forms.Form]::new()
    $form.Text = $s.windowTitle
    $form.Size = [System.Drawing.Size]::new(1080, 720)
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = [System.Drawing.Size]::new(860, 560)
    try {
        $iconPath = Join-Path $module.ModuleBase 'domovoy.ico'
        if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
            $form.Icon = [System.Drawing.Icon]::new($iconPath)
        }
    } catch { }

    $output = [System.Windows.Forms.TextBox]::new()
    $output.Multiline = $true
    $output.ReadOnly = $true
    $output.ScrollBars = 'Vertical'
    $output.Dock = 'Bottom'
    $output.Height = 210
    $output.Font = [System.Drawing.Font]::new('Consolas', 9)
    $output.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 28)
    $output.ForeColor = [System.Drawing.Color]::Gainsboro

    $featureBar = [System.Windows.Forms.FlowLayoutPanel]::new()
    $featureBar.Dock = 'Bottom'
    $featureBar.Height = 44
    $featureBar.Padding = [System.Windows.Forms.Padding]::new(4)

    $searchPanel = [System.Windows.Forms.FlowLayoutPanel]::new()
    $searchPanel.Dock = 'Top'
    $searchPanel.Height = 38
    $searchPanel.Padding = [System.Windows.Forms.Padding]::new(4)

    $toolbar = [System.Windows.Forms.FlowLayoutPanel]::new()
    $toolbar.Dock = 'Top'
    $toolbar.Height = 44
    $toolbar.Padding = [System.Windows.Forms.Padding]::new(4)

    $statusStrip = [System.Windows.Forms.StatusStrip]::new()
    $statusLabel = [System.Windows.Forms.ToolStripStatusLabel]::new()
    $statusLabel.Spring = $true
    $statusLabel.TextAlign = 'MiddleLeft'
    $statusLabel.Text = $s.statusReady
    $adminLabel = [System.Windows.Forms.ToolStripStatusLabel]::new()
    $adminLabel.Text = if ($isAdmin) { $s.adminStatusAdmin } else { $s.adminStatusUser }
    $versionLabel = [System.Windows.Forms.ToolStripStatusLabel]::new()
    $versionLabel.Text = 'v{0}' -f $module.Version
    $null = $statusStrip.Items.Add($statusLabel)
    $null = $statusStrip.Items.Add($adminLabel)
    $null = $statusStrip.Items.Add($versionLabel)

    $list = [System.Windows.Forms.ListView]::new()
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.MultiSelect = $false
    $list.HideSelection = $false
    $list.Dock = 'Fill'
    # DoubleBuffered is protected - kill the repaint flicker through
    # reflection, but never let it break the build.
    try {
        $doubleBuffered = $list.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance, NonPublic')
        if ($doubleBuffered) { $doubleBuffered.SetValue($list, $true) }
    } catch { }
    $null = $list.Columns.Add($s.columnId, 240)
    $null = $list.Columns.Add($s.columnTitle, 430)
    $null = $list.Columns.Add($s.columnRisk, 60)
    $null = $list.Columns.Add($s.columnJournal, 90)

    # Docking is processed from the last control added to the first:
    # toolbar and search take the top, status strip and output take the
    # bottom, featureBar sits just above the output, the list fills
    # whatever remains.
    $null = $form.Controls.Add($list)
    $null = $form.Controls.Add($featureBar)
    $null = $form.Controls.Add($output)
    $null = $form.Controls.Add($statusStrip)
    $null = $form.Controls.Add($searchPanel)
    $null = $form.Controls.Add($toolbar)

    # ---- search controls (before the catalog closures that read them) -------

    $searchLabelControl = [System.Windows.Forms.Label]::new()
    $searchLabelControl.Text = $s.searchLabel
    $searchLabelControl.AutoSize = $true
    $searchLabelControl.Margin = [System.Windows.Forms.Padding]::new(3, 9, 3, 3)

    $searchBox = [System.Windows.Forms.TextBox]::new()
    $searchBox.Width = 240

    $countLabel = [System.Windows.Forms.Label]::new()
    $countLabel.Text = ''
    $countLabel.AutoSize = $true
    $countLabel.ForeColor = [System.Drawing.Color]::DimGray
    $countLabel.Margin = [System.Windows.Forms.Padding]::new(12, 9, 3, 3)

    $null = $searchPanel.Controls.Add($searchLabelControl)
    $null = $searchPanel.Controls.Add($searchBox)
    $null = $searchPanel.Controls.Add($countLabel)

    # ---- output helpers -----------------------------------------------------

    $append = {
        param([string]$Text)
        $output.AppendText($Text + [Environment]::NewLine)
        $output.ScrollToCaret()
    }.GetNewClosure()

    # ---- catalog: refresh + filter (needed by the drain handler) ------------

    # Rebuilds the in-memory catalog + journal map. The list itself is
    # rendered by applyFilter so the search box can narrow it live.
    $refreshCatalog = {
        $state.features = @(Get-DomovoyFeature)
        $journal = @{}
        try {
            foreach ($record in @(Get-DomovoyLedger -Last 1000000)) {
                if ($record.event -eq 'feature.apply') {
                    $journal[$record.featureId] = 'feature.apply'
                }
                elseif ($record.event -eq 'feature.undo') {
                    $journal[$record.featureId] = 'feature.undo'
                }
            }
        }
        catch { }
        $state.journal = $journal
    }.GetNewClosure()

    $applyFilter = {
        $list.BeginUpdate()
        try {
            $list.Items.Clear()
            $filter = ''
            if ($searchBox.Text) { $filter = $searchBox.Text.Trim() }
            $sLive = & $stringsLive
            $shown = 0
            foreach ($feature in $state.features) {
                if ($filter) {
                    $hay = '{0} {1} {2}' -f $feature.Id, $feature.Title, $feature.Risk
                    if ($hay -notlike "*$filter*") { continue }
                }
                $item = [System.Windows.Forms.ListViewItem]::new([string]$feature.Id)
                $null = $item.SubItems.Add([string]$feature.Title)
                $null = $item.SubItems.Add([string]$feature.Risk)
                $journalText = ''
                $journalEvent = $state.journal[[string]$feature.Id]
                if ($journalEvent -eq 'feature.apply') { $journalText = $sLive.journalApplied }
                elseif ($journalEvent -eq 'feature.undo') { $journalText = $sLive.journalUndone }
                $null = $item.SubItems.Add($journalText)
                $null = $list.Items.Add($item)
                $shown++
            }
            $countLabel.Text = $sLive.filterCount -f $shown, @($state.features).Count
        }
        finally {
            $list.EndUpdate()
        }
    }.GetNewClosure()

    $fillList = {
        & $refreshCatalog
        $selectedId = $null
        if ($list.SelectedItems.Count -gt 0) {
            $selectedId = [string]$list.SelectedItems[0].Text
        }
        & $applyFilter
        if ($selectedId) {
            foreach ($item in $list.Items) {
                if ([string]$item.Text -eq $selectedId) {
                    $item.Selected = $true
                    $item.Focused = $true
                    break
                }
            }
        }
    }.GetNewClosure()

    $state.fillList = $fillList

    $selectedId = {
        $item = $list.SelectedItems | Select-Object -First 1
        if ($item) {
            return [string]$item.Text
        }
        return $null
    }.GetNewClosure()

    # ---- async worker: queue + timer (the UI never blocks) -------------------

    # The action runs in a fresh PowerShell runspace (the module is imported
    # there from the same manifest), so the UI thread never blocks and the
    # window never degrades into "(Not responding)". Results travel through
    # a synchronized queue; the timer (or a manual Drain in tests) marshals
    # them onto the UI thread. The thin-client rule holds: the worker runs
    # the exact CLI line, nothing else.
    $workerBody = @'
param([string]$Cli, [string]$ModulePath, [System.Collections.Queue]$Queue)
try {
    Import-Module -Name $ModulePath -Global -ErrorAction Stop
    $rendered = & ([scriptblock]::Create($Cli)) 2>&1 | Out-String -Width 110
    $Queue.Enqueue(@('out', [string]$rendered))
    $Queue.Enqueue(@('done', $null))
}
catch {
    try { $Queue.Enqueue(@('err', $_.Exception.Message)) } catch { }
    try { $Queue.Enqueue(@('done', $null)) } catch { }
}
'@

    $statusBusy = {
        param([string]$CliLine)
        $statusLabel.Text = (& $stringsLive).statusRunning -f $CliLine
    }.GetNewClosure()

    $startAction = {
        param([string]$CliLine, [scriptblock]$PostAction)
        if ($state.busy) {
            & $append ((& $stringsLive).busySkip)
            return
        }
        $modulePath = (Get-Module -Name Domovoy).Path
        $state.busy = $true
        $state.cancelled = $false
        $state.hadOutput = $false
        $state.postAction = $PostAction
        & $append ((& $stringsLive).cliPrefix + $CliLine)
        & $statusBusy $CliLine
        $form.UseWaitCursor = $true
        foreach ($b in $state.actionButtons) { $b.Enabled = $false }
        if ($state.stopButton) { $state.stopButton.Enabled = $true }
        $worker = [powershell]::Create()
        $null = $worker.AddScript($workerBody)
        $null = $worker.AddArgument($CliLine)
        $null = $worker.AddArgument($modulePath)
        $null = $worker.AddArgument($uiQueue)
        $state.worker = $worker
        $state.handle = $worker.BeginInvoke()
    }.GetNewClosure()

    $drainUi = {
        if (-not $state.busy) { return }
        $sLive = & $stringsLive
        $chunks = @()
        while ($uiQueue.Count -gt 0) { $chunks += ,$uiQueue.Dequeue() }
        foreach ($chunk in $chunks) {
            $kind = [string]$chunk[0]
            if ($kind -eq 'out') {
                $text = ([string]$chunk[1]).TrimEnd()
                if ($text) {
                    & $append $text
                    $state.hadOutput = $true
                }
            }
            elseif ($kind -eq 'err') {
                & $append ($sLive.errorPrefix + [string]$chunk[1])
            }
            elseif ($kind -eq 'done') {
                if (-not $state.hadOutput) { & $append ($sLive.noOutput) }
                if ($state.cancelled) {
                    & $append $sLive.statusCancelled
                    $statusLabel.Text = $sLive.statusCancelled
                }
                else {
                    $statusLabel.Text = $sLive.statusReady
                }
                try { $null = $state.worker.EndInvoke($state.handle) } catch { }
                try { $state.worker.Dispose() } catch { }
                $state.worker = $null
                $state.handle = $null
                $state.busy = $false
                $form.UseWaitCursor = $false
                foreach ($b in $state.actionButtons) { $b.Enabled = $true }
                if ($state.stopButton) { $state.stopButton.Enabled = $false }
                if ($state.postAction) {
                    try { & $state.postAction } catch { }
                    $state.postAction = $null
                }
                if ($state.fillList) { & $state.fillList }
                & $append ('-' * 72)
            }
        }
    }.GetNewClosure()

    $uiTimer = [System.Windows.Forms.Timer]::new()
    $uiTimer.Interval = 150
    $uiTimer.Add_Tick($drainUi)

    $stopClick = {
        if ($state.busy -and $state.worker) {
            $state.cancelled = $true
            & $append ((& $stringsLive).stopRequested)
            try { $state.worker.Stop() } catch { }
        }
    }.GetNewClosure()

    # ---- buttons ------------------------------------------------------------

    $newButton = {
        param([string]$Label)
        $button = [System.Windows.Forms.Button]::new()
        $button.Text = $Label
        $button.AutoSize = $true
        return $button
    }

    # ---- per-feature handlers ----------------------------------------------

    $dryRunClick = {
        try {
            $id = & $selectedId
            if (-not $id) {
                & $append (& $stringsLive).selectFirst
                return
            }
            $cli = "Invoke-DomovoyFeature -Id '$id'"
            & $startAction $cli
        }
        catch {
            & $append ((& $stringsLive).errorPrefix + $_.Exception.Message)
        }
    }.GetNewClosure()

    $btnDryRun = & $newButton $s.btnDryRun
    $btnDryRun.Add_Click($dryRunClick)

    $applyClick = {
        try {
            $id = & $selectedId
            if (-not $id) {
                & $append (& $stringsLive).selectFirst
                return
            }
            $cli = "Invoke-DomovoyFeature -Id '$id' -Apply"
            $answer = [System.Windows.Forms.MessageBox]::Show($form, ((& $stringsLive).applyConfirm -f $cli), (& $stringsLive).messageBoxTitle, 'YesNo', 'Warning')
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                & $append (& $stringsLive).cancelled
                return
            }
            & $startAction $cli
        }
        catch {
            & $append ((& $stringsLive).errorPrefix + $_.Exception.Message)
        }
    }.GetNewClosure()

    $btnApply = & $newButton $s.btnApply
    $btnApply.Add_Click($applyClick)

    $undoClick = {
        try {
            $id = & $selectedId
            if (-not $id) {
                & $append (& $stringsLive).selectFirst
                return
            }
            $cli = "Undo-DomovoyFeature -Id '$id' -Apply"
            $answer = [System.Windows.Forms.MessageBox]::Show($form, ((& $stringsLive).undoConfirm -f $cli), (& $stringsLive).messageBoxTitle, 'YesNo', 'Warning')
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                & $append (& $stringsLive).cancelled
                return
            }
            & $startAction $cli
        }
        catch {
            & $append ((& $stringsLive).errorPrefix + $_.Exception.Message)
        }
    }.GetNewClosure()

    $btnUndo = & $newButton $s.btnUndo
    $btnUndo.Add_Click($undoClick)

    $effectClick = {
        try {
            $id = & $selectedId
            if (-not $id) {
                & $append (& $stringsLive).selectFirst
                return
            }
            $cli = "Test-DomovoyEffect -Id '$id'"
            & $startAction $cli
        }
        catch {
            & $append ((& $stringsLive).errorPrefix + $_.Exception.Message)
        }
    }.GetNewClosure()

    $btnEffect = & $newButton $s.btnEffect
    $btnEffect.Add_Click($effectClick)

    foreach ($button in @($btnDryRun, $btnApply, $btnUndo, $btnEffect)) {
        $null = $featureBar.Controls.Add($button)
    }

    # A double click on a feature is the same as a dry-run: the most common
    # "what would this do" question, one gesture away (Windows UX guide:
    # optimize the frequent path).
    $list.Add_DoubleClick({ & $dryRunClick }.GetNewClosure())

    # ---- toolbar handlers ---------------------------------------------------

    $driftClick = {
        try { & $startAction 'Invoke-DomovoyDriftScan' } catch { & $append ((& $stringsLive).errorPrefix + $_.Exception.Message) }
    }.GetNewClosure()
    $btnDrift = & $newButton $s.btnDriftScan
    $btnDrift.Add_Click($driftClick)

    $changesClick = {
        try { & $startAction 'Get-DomovoyChangeReport -Last 20' } catch { & $append ((& $stringsLive).errorPrefix + $_.Exception.Message) }
    }.GetNewClosure()
    $btnChanges = & $newButton $s.btnChangeReport
    $btnChanges.Add_Click($changesClick)

    $networkClick = {
        try { & $startAction 'Get-DomovoyNetworkReport' } catch { & $append ((& $stringsLive).errorPrefix + $_.Exception.Message) }
    }.GetNewClosure()
    $btnNetwork = & $newButton $s.btnNetworkReport
    $btnNetwork.Add_Click($networkClick)

    $autoHealClick = {
        try { & $startAction 'Invoke-DomovoyAutoHeal' } catch { & $append ((& $stringsLive).errorPrefix + $_.Exception.Message) }
    }.GetNewClosure()
    $btnAutoHeal = & $newButton $s.btnAutoHeal
    $btnAutoHeal.Add_Click($autoHealClick)

    $themeClick = {
        try {
            $cli = 'Switch-DomovoyTheme -Apply'
            $answer = [System.Windows.Forms.MessageBox]::Show($form, ((& $stringsLive).themeConfirm -f $cli), (& $stringsLive).messageBoxTitle, 'YesNo', 'Warning')
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                & $append (& $stringsLive).cancelled
                return
            }
            & $startAction $cli
        }
        catch {
            & $append ((& $stringsLive).errorPrefix + $_.Exception.Message)
        }
    }.GetNewClosure()
    $btnTheme = & $newButton $s.btnSwitchTheme
    $btnTheme.Add_Click($themeClick)

    $policiesClick = {
        try { & $startAction 'Export-DomovoyPolicy' } catch { & $append ((& $stringsLive).errorPrefix + $_.Exception.Message) }
    }.GetNewClosure()
    $btnPolicies = & $newButton $s.btnExportPolicies
    $btnPolicies.Add_Click($policiesClick)

    $refreshClick = {
        try {
            & $fillList
            & $append (& $stringsLive).refreshed
        }
        catch {
            & $append ((& $stringsLive).errorPrefix + $_.Exception.Message)
        }
    }.GetNewClosure()
    $btnRefresh = & $newButton $s.btnRefresh
    $btnRefresh.Add_Click($refreshClick)

    $btnLanguage = & $newButton ((Get-DomovoyStrings).btnLanguage -f (Get-DomovoyLanguage).Language)
    $languageClick = {
        try {
            $target = if ((Get-DomovoyLanguage).Language -eq 'ru') { 'en' } else { 'ru' }
            $cli = "Set-DomovoyLanguage -Language $target"
            $relabel = {
                $btnLanguage.Text = (& $stringsLive).btnLanguage -f $target
            }.GetNewClosure()
            & $startAction $cli $relabel
        }
        catch {
            & $append ((& $stringsLive).errorPrefix + $_.Exception.Message)
        }
    }.GetNewClosure()
    $btnLanguage.Add_Click($languageClick)

    foreach ($button in @($btnDrift, $btnChanges, $btnNetwork, $btnAutoHeal, $btnTheme, $btnPolicies, $btnRefresh, $btnLanguage)) {
        $null = $toolbar.Controls.Add($button)
    }

    # The Stop control lives in the status strip; it is enabled only while
    # an action is running (startAction/drain reach it through $state).
    $stopButton = [System.Windows.Forms.Button]::new()
    $stopButton.Text = $s.btnStop
    $stopButton.AutoSize = $true
    $stopButton.Enabled = $false
    $stopButton.Add_Click($stopClick)
    $state.stopButton = $stopButton
    $stopHost = [System.Windows.Forms.ToolStripControlHost]::new($stopButton)
    $null = $statusStrip.Items.Insert(1, $stopHost)

    # A non-admin session gets a one-click UAC elevation instead of cryptic
    # access-denied output from every HKLM/service feature.
    if (-not $isAdmin) {
        $elevateButton = & $newButton $s.btnElevate
        $elevateClick = {
            try {
                $currentModule = Get-Module -Name Domovoy
                $shim = Join-Path $currentModule.ModuleBase 'domovoy.ps1'
                if (-not (Test-Path -LiteralPath $shim -PathType Leaf)) {
                    throw 'domovoy.ps1 was not found next to the module (an install without the CLI shim cannot self-elevate).'
                }
                $engine = (Get-Process -Id $PID).Path
                Start-Process -FilePath $engine -Verb RunAs -ArgumentList @(
                    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                    '-File', $shim, 'Show-Domovoy')
                & $append ((& $stringsLive).elevateStarted)
            }
            catch {
                & $append ((& $stringsLive).elevateFailed -f $_.Exception.Message)
            }
        }.GetNewClosure()
        $elevateButton.Add_Click($elevateClick)
        $null = $toolbar.Controls.Add($elevateButton)
    }

    # Buttons that must go dark while an action runs (the queue-guard in
    # startAction makes double-submits impossible anyway). Assigned through
    # $state because startAction/drainUi were bound earlier.
    $state.actionButtons = @($btnDryRun, $btnApply, $btnUndo, $btnEffect, $btnDrift, $btnChanges, $btnNetwork, $btnAutoHeal, $btnTheme, $btnPolicies, $btnRefresh, $btnLanguage)

    $searchBox.Add_TextChanged($applyFilter)

    # ---- shutdown hygiene ---------------------------------------------------

    $form.Add_FormClosed({
        param($sender, $e)
        try { $uiTimer.Stop() } catch { }
        try { $uiTimer.Dispose() } catch { }
        try {
            if ($state.worker) {
                $state.worker.Stop()
                $state.worker.Dispose()
            }
        } catch { }
    }.GetNewClosure())

    # ---- run ---------------------------------------------------------------

    $welcome = @(
        ($s.welcome1 -f $module.Version),
        $s.welcome2,
        ''
    )
    if (-not $isAdmin) {
        $welcome += $s.welcomeNoAdmin
    }

    foreach ($line in $welcome) {
        & $append $line
    }
    & $fillList

    if ($Preview) {
        # The live test surface. The timer is NOT started in preview: tests
        # drive the queue manually through Drain (deterministic, no message
        # loop required on headless CI runners).
        $form.Tag = @{
            List     = $list
            Output   = $output
            Status   = $statusLabel
            Search   = $searchBox
            Drain    = $drainUi
            State    = $state
            Timer    = $uiTimer
            Buttons  = @{
                DryRun  = $btnDryRun
                Apply   = $btnApply
                Undo    = $btnUndo
                Effect  = $btnEffect
                Changes = $btnChanges
                Refresh = $btnRefresh
                Stop    = $stopButton
            }
            Handlers = @{
                DryRun  = $dryRunClick
                Apply   = $applyClick
                Undo    = $undoClick
                Effect  = $effectClick
                Changes = $changesClick
                Refresh = $refreshClick
            }
            # A probe bound exactly like the click handlers (.GetNewClosure
            # over the bridge variable): the tests invoke it headlessly and
            # prove the closure/session-state mechanics without WinForms click
            # plumbing (a .NET 9+ PerformClick on a never-created handle is a
            # silent no-op, and the preview form is never shown).
            Probe = { (& $stringsLive).selectFirst }.GetNewClosure()
        }
        return $form
    }

    $uiTimer.Start()
    $null = $form.ShowDialog()
    $form.Dispose()
}
