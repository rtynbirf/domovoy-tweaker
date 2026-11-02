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
    change report, network report, auto-heal, theme switch, policy export).

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

    # ---- data --------------------------------------------------------------

    $welcome = @(
        ('Domovoy GUI - thin client over the CLI (module {0}).' -f (Get-Module -Name Domovoy).Version),
        'Every action below first prints the CLI command it runs, then runs exactly that command.',
        ''
    )

    # ---- controls ----------------------------------------------------------

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'Domovoy - the ledger-based Windows tweaker'
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
    $null = $list.Columns.Add('Id', 240)
    $null = $list.Columns.Add('Title', 430)
    $null = $list.Columns.Add('Risk', 60)
    $null = $list.Columns.Add('Journal', 90)

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
        & $append ('CLI: ' + $CliLine)
        try {
            $result = & $Action
            if ($null -ne $result) {
                & $append (($result | Out-String -Width 110).TrimEnd())
            }
            else {
                & $append '(no output)'
            }
        }
        catch {
            & $append ('ERROR: ' + $_.Exception.Message)
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

    $btnDryRun = & $newButton 'Dry-run'
    $btnDryRun.Add_Click({
        $id = & $selectedId
        if (-not $id) {
            & $append 'Select a feature first.'
            return
        }
        $cli = "Invoke-DomovoyFeature -Id '$id'"
        & $runAction $cli ([scriptblock]::Create($cli))
    }.GetNewClosure())

    $btnApply = & $newButton 'Apply...'
    $btnApply.Add_Click({
        $id = & $selectedId
        if (-not $id) {
            & $append 'Select a feature first.'
            return
        }
        $cli = "Invoke-DomovoyFeature -Id '$id' -Apply"
        $answer = [System.Windows.Forms.MessageBox]::Show($form, ("Run: {0}`n`nA snapshot is taken before the change; undo stays available." -f $cli), 'Domovoy', 'YesNo', 'Warning')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            & $append 'Cancelled.'
            return
        }
        & $runAction $cli ([scriptblock]::Create($cli))
    }.GetNewClosure())

    $btnUndo = & $newButton 'Undo...'
    $btnUndo.Add_Click({
        $id = & $selectedId
        if (-not $id) {
            & $append 'Select a feature first.'
            return
        }
        $cli = "Undo-DomovoyFeature -Id '$id' -Apply"
        $answer = [System.Windows.Forms.MessageBox]::Show($form, ("Run: {0}" -f $cli), 'Domovoy', 'YesNo', 'Warning')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            & $append 'Cancelled.'
            return
        }
        & $runAction $cli ([scriptblock]::Create($cli))
    }.GetNewClosure())

    $btnEffect = & $newButton 'Effect'
    $btnEffect.Add_Click({
        $id = & $selectedId
        if (-not $id) {
            & $append 'Select a feature first.'
            return
        }
        $cli = "Test-DomovoyEffect -Id '$id'"
        & $runAction $cli ([scriptblock]::Create($cli))
    }.GetNewClosure())

    foreach ($button in @($btnDryRun, $btnApply, $btnUndo, $btnEffect)) {
        $null = $featureBar.Controls.Add($button)
    }

    # ---- toolbar buttons ---------------------------------------------------

    $btnDrift = & $newButton 'Drift scan'
    $btnDrift.Add_Click({
        & $runAction 'Invoke-DomovoyDriftScan' ([scriptblock]::Create('Invoke-DomovoyDriftScan'))
    }.GetNewClosure())

    $btnChanges = & $newButton 'Change report'
    $btnChanges.Add_Click({
        & $runAction 'Get-DomovoyChangeReport -Last 20' ([scriptblock]::Create('Get-DomovoyChangeReport -Last 20'))
    }.GetNewClosure())

    $btnNetwork = & $newButton 'Network report'
    $btnNetwork.Add_Click({
        & $runAction 'Get-DomovoyNetworkReport' ([scriptblock]::Create('Get-DomovoyNetworkReport'))
    }.GetNewClosure())

    $btnAutoHeal = & $newButton 'Auto-heal (dry-run)'
    $btnAutoHeal.Add_Click({
        & $runAction 'Invoke-DomovoyAutoHeal' ([scriptblock]::Create('Invoke-DomovoyAutoHeal'))
    }.GetNewClosure())

    $btnTheme = & $newButton 'Switch theme'
    $btnTheme.Add_Click({
        $cli = 'Switch-DomovoyTheme -Apply'
        $answer = [System.Windows.Forms.MessageBox]::Show($form, ("Run: {0}`n`nThe theme toggles between dark and light; the previous values stay undo-able." -f $cli), 'Domovoy', 'YesNo', 'Warning')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            & $append 'Cancelled.'
            return
        }
        & $runAction $cli ([scriptblock]::Create($cli))
    }.GetNewClosure())

    $btnPolicies = & $newButton 'Export policies'
    $btnPolicies.Add_Click({
        & $runAction 'Export-DomovoyPolicy' ([scriptblock]::Create('Export-DomovoyPolicy'))
    }.GetNewClosure())

    $btnRefresh = & $newButton 'Refresh'
    $btnRefresh.Add_Click({
        & $fillList
        & $append 'Feature list refreshed.'
    }.GetNewClosure())

    foreach ($button in @($btnDrift, $btnChanges, $btnNetwork, $btnAutoHeal, $btnTheme, $btnPolicies, $btnRefresh)) {
        $null = $toolbar.Controls.Add($button)
    }

    # ---- run ---------------------------------------------------------------

    foreach ($line in $welcome) {
        & $append $line
    }
    & $fillList

    if ($Preview) {
        # Expose the two live controls so tests can assert on the built form.
        $form.Tag = @{
            List = $list
            Output = $output
        }
        return $form
    }

    $null = $form.ShowDialog()
    $form.Dispose()
}
