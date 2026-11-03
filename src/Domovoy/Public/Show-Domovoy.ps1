function Show-Domovoy {
    <#
    .SYNOPSIS
    Opens the Domovoy GUI: a thin WinForms client over the CLI (v0.7.0).

    .DESCRIPTION
    Every action the GUI can perform is one exact CLI command: the button
    first prints the command line ("CLI: Invoke-DomovoyFeature -Id ...") and
    then runs that very line, compiled into a scriptblock. No logic is
    duplicated - snapshots, dry-runs, elevation checks, verification probes
    and journal events all happen inside the same public commands you would
    call by hand. If the GUI disappeared tomorrow, everything it does would
    still be one command away.

    The window shows the feature catalog with the journal status of every
    feature, buttons for the per-feature contour (dry-run / apply / undo /
    effect report) and a toolbar for the machine-wide contours (drift scan,
    change report, network report, auto-heal, theme switch, policy export,
    language switch). Every user-facing sentence comes from the strings
    table (Get-DomovoyStrings, v1.6 item 6): the window builds in the
    active language, the Language toolbar button switches en/ru for the
    session and writes the preference, and the dynamic messages resolve
    the table live so a switch is visible without reopening.

    .PARAMETER Preview
    Builds the whole window, wires every handler, appends the welcome text
    and returns the Form object without showing it. Used by the tests (and
    handy for smoke checks); the caller owns disposal.

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
    # regression test in Domovoy.V07.Tests.ps1 (PerformClick on the preview
    # form), which fails on the pre-fix code.
    $stringsLive = { Get-DomovoyStrings }

    # ---- data --------------------------------------------------------------

    $welcome = @(
        ($s.welcome1 -f (Get-Module -Name Domovoy).Version),
        $s.welcome2,
        ''
    )

    # ---- controls ----------------------------------------------------------

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = $s.windowTitle
    $form.Size = [System.Drawing.Size]::new(1040, 680)
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = [System.Drawing.Size]::new(820, 520)

    $output = [System.Windows.Forms.TextBox]::new()
    $output.Multiline = $true
    $output.ReadOnly = $true
    $output.ScrollBars = 'Vertical'
    $output.Dock = 'Bottom'
    $output.Height = 240
    $output.Font = [System.Drawing.Font]::new('Consolas', 9)
    $output.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 28)
    $output.ForeColor = [System.Drawing.Color]::Gainsboro

    $featureBar = [System.Windows.Forms.FlowLayoutPanel]::new()
    $featureBar.Dock = 'Bottom'
    $featureBar.Height = 44
    $featureBar.Padding = [System.Windows.Forms.Padding]::new(4)

    $toolbar = [System.Windows.Forms.FlowLayoutPanel]::new()
    $toolbar.Dock = 'Top'
    $toolbar.Height = 44
    $toolbar.Padding = [System.Windows.Forms.Padding]::new(4)

    $list = [System.Windows.Forms.ListView]::new()
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.MultiSelect = $false
    $list.HideSelection = $false
    $list.Dock = 'Fill'
    $null = $list.Columns.Add($s.columnId, 240)
    $null = $list.Columns.Add($s.columnTitle, 430)
    $null = $list.Columns.Add($s.columnRisk, 60)
    $null = $list.Columns.Add($s.columnJournal, 90)

    # Docking is processed from the last control added to the first:
    # toolbar takes the top, output takes the bottom, featureBar sits just
    # above the output, the list fills whatever remains.
    $null = $form.Controls.Add($list)
    $null = $form.Controls.Add($featureBar)
    $null = $form.Controls.Add($output)
    $null = $form.Controls.Add($toolbar)

    # ---- output helpers ----------------------------------------------------

    $append = {
        param([string]$Text)
        $output.AppendText($Text + [Environment]::NewLine)
        $output.ScrollToCaret()
    }.GetNewClosure()

    $runAction = {
        param([string]$CliLine, [scriptblock]$Action)
        & $append ((& $stringsLive).cliPrefix + $CliLine)
        try {
            $result = & $Action
            if ($null -ne $result) {
                & $append (($result | Out-String -Width 110).TrimEnd())
            }
            else {
                & $append (& $stringsLive).noOutput
            }
        }
        catch {
            & $append ((& $stringsLive).errorPrefix + $_.Exception.Message)
        }
        & $append ('-' * 72)
    }.GetNewClosure()

    $selectedId = {
        $item = $list.SelectedItems | Select-Object -First 1
        if ($item) {
            return [string]$item.Text
        }
        return $null
    }.GetNewClosure()

    # Rebuilds the feature list from the catalog + journal. Defined after the
    # controls exist and closure-bound: when a click handler calls it later,
    # the function locals ($list) are only reachable through the closure.
    $fillList = {
        $list.Items.Clear()
        $statuses = @{}
        try {
            foreach ($record in @(Get-DomovoyLedger -Last 1000000)) {
                if ($record.event -eq 'feature.apply') {
                    $statuses[$record.featureId] = 'applied'
                }
                elseif ($record.event -eq 'feature.undo') {
                    $statuses[$record.featureId] = 'undone'
                }
            }
        }
        catch { }
        foreach ($feature in @(Get-DomovoyFeature)) {
            $item = [System.Windows.Forms.ListViewItem]::new([string]$feature.Id)
            $null = $item.SubItems.Add([string]$feature.Title)
            $null = $item.SubItems.Add([string]$feature.Risk)
            $null = $item.SubItems.Add([string]$statuses[$feature.Id])
            $null = $list.Items.Add($item)
        }
    }.GetNewClosure()

    $newButton = {
        param([string]$Label)
        $button = [System.Windows.Forms.Button]::new()
        $button.Text = $Label
        $button.AutoSize = $true
        return $button
    }

    # ---- per-feature buttons ----------------------------------------------

    $btnDryRun = & $newButton $s.btnDryRun
    $btnDryRun.Add_Click({
        $id = & $selectedId
        if (-not $id) {
            & $append (& $stringsLive).selectFirst
            return
        }
        $cli = "Invoke-DomovoyFeature -Id '$id'"
        & $runAction $cli ([scriptblock]::Create($cli))
    }.GetNewClosure())

    $btnApply = & $newButton $s.btnApply
    $btnApply.Add_Click({
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
        & $runAction $cli ([scriptblock]::Create($cli))
    }.GetNewClosure())

    $btnUndo = & $newButton $s.btnUndo
    $btnUndo.Add_Click({
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
        & $runAction $cli ([scriptblock]::Create($cli))
    }.GetNewClosure())

    $btnEffect = & $newButton $s.btnEffect
    $btnEffect.Add_Click({
        $id = & $selectedId
        if (-not $id) {
            & $append (& $stringsLive).selectFirst
            return
        }
        $cli = "Test-DomovoyEffect -Id '$id'"
        & $runAction $cli ([scriptblock]::Create($cli))
    }.GetNewClosure())

    foreach ($button in @($btnDryRun, $btnApply, $btnUndo, $btnEffect)) {
        $null = $featureBar.Controls.Add($button)
    }

    # ---- toolbar buttons ---------------------------------------------------

    $btnDrift = & $newButton $s.btnDriftScan
    $btnDrift.Add_Click({
        & $runAction 'Invoke-DomovoyDriftScan' ([scriptblock]::Create('Invoke-DomovoyDriftScan'))
    }.GetNewClosure())

    $btnChanges = & $newButton $s.btnChangeReport
    $btnChanges.Add_Click({
        & $runAction 'Get-DomovoyChangeReport -Last 20' ([scriptblock]::Create('Get-DomovoyChangeReport -Last 20'))
    }.GetNewClosure())

    $btnNetwork = & $newButton $s.btnNetworkReport
    $btnNetwork.Add_Click({
        & $runAction 'Get-DomovoyNetworkReport' ([scriptblock]::Create('Get-DomovoyNetworkReport'))
    }.GetNewClosure())

    $btnAutoHeal = & $newButton $s.btnAutoHeal
    $btnAutoHeal.Add_Click({
        & $runAction 'Invoke-DomovoyAutoHeal' ([scriptblock]::Create('Invoke-DomovoyAutoHeal'))
    }.GetNewClosure())

    $btnTheme = & $newButton $s.btnSwitchTheme
    $btnTheme.Add_Click({
        $cli = 'Switch-DomovoyTheme -Apply'
        $answer = [System.Windows.Forms.MessageBox]::Show($form, ((& $stringsLive).themeConfirm -f $cli), (& $stringsLive).messageBoxTitle, 'YesNo', 'Warning')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            & $append (& $stringsLive).cancelled
            return
        }
        & $runAction $cli ([scriptblock]::Create($cli))
    }.GetNewClosure())

    $btnPolicies = & $newButton $s.btnExportPolicies
    $btnPolicies.Add_Click({
        & $runAction 'Export-DomovoyPolicy' ([scriptblock]::Create('Export-DomovoyPolicy'))
    }.GetNewClosure())

    $btnRefresh = & $newButton $s.btnRefresh
    $btnRefresh.Add_Click({
        & $fillList
        & $append (& $stringsLive).refreshed
    }.GetNewClosure())

    $btnLanguage = & $newButton ((Get-DomovoyStrings).btnLanguage -f (Get-DomovoyLanguage).Language)
    $btnLanguage.Add_Click({
        $target = if ((Get-DomovoyLanguage).Language -eq 'ru') { 'en' } else { 'ru' }
        $cli = "Set-DomovoyLanguage -Language $target"
        & $runAction $cli ([scriptblock]::Create($cli))
        $sLive = & $stringsLive
        & $append ($sLive.languageSwitched -f $target)
        $btnLanguage.Text = $sLive.btnLanguage -f $target
    }.GetNewClosure())

    foreach ($button in @($btnDrift, $btnChanges, $btnNetwork, $btnAutoHeal, $btnTheme, $btnPolicies, $btnRefresh, $btnLanguage)) {
        $null = $toolbar.Controls.Add($button)
    }

    # ---- run ---------------------------------------------------------------

    foreach ($line in $welcome) {
        & $append $line
    }
    & $fillList

    if ($Preview) {
        # Expose the two live controls so tests can assert on the built form.
        # The Buttons expose the live click surface so the regression test
        # can PerformClick() them headlessly (v1.5.4 closure regression).
        $form.Tag = @{
            List = $list
            Output = $output
            Buttons = @{
                DryRun = $btnDryRun
                Changes = $btnChanges
                Refresh = $btnRefresh
            }
        }
        return $form
    }

    $null = $form.ShowDialog()
    $form.Dispose()
}
