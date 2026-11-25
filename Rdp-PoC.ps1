# Remote Workspace - Phase 1: embedded RDP feasibility test
# Windows PowerShell 5.1, STA. No credentials stored.
$ErrorActionPreference = 'Stop'
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Run with powershell.exe -STA -File Rdp-PoC.ps1' }
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
if (-not ('RdpProbeHost' -as [type])) {
    Add-Type -ReferencedAssemblies 'System.Windows.Forms.dll','System.Drawing.dll','Microsoft.CSharp.dll','System.Core.dll' -TypeDefinition @'
using System;
using System.Windows.Forms;
public sealed class RdpProbeHost : AxHost {
    public RdpProbeHost() : base("A0C63C30-F08D-4AB4-907C-34905D770C7D") {}
    public void OpenSession(string server, string user) {
        dynamic rdp = GetOcx();
        rdp.Server = server;
        if (!String.IsNullOrWhiteSpace(user)) rdp.UserName = user;
        rdp.DesktopWidth = Math.Max(640, Width);
        rdp.DesktopHeight = Math.Max(480, Height);
        rdp.AdvancedSettings9.EnableCredSspSupport = true;
        rdp.AdvancedSettings9.AuthenticationLevel = 1u;
        rdp.AdvancedSettings9.SmartSizing = true;
        rdp.Connect();
    }
    public int ConnectionState() { dynamic rdp = GetOcx(); return (int)rdp.Connected; }
    public void DisconnectSession() { dynamic rdp = GetOcx(); if (rdp.Connected != 0) rdp.Disconnect(); }
}
'@
}
[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = 'Remote Workspace - RDP proof of concept'
$form.Size = New-Object Drawing.Size(1200,800)
$form.StartPosition = 'CenterScreen'
$bar = New-Object Windows.Forms.FlowLayoutPanel
$bar.Dock = 'Top'; $bar.Height = 45; $bar.Padding = New-Object Windows.Forms.Padding(6); $bar.WrapContents = $false
$server = New-Object Windows.Forms.TextBox; $server.Width = 230
$user = New-Object Windows.Forms.TextBox; $user.Width = 200
$connect = New-Object Windows.Forms.Button; $connect.Text = 'Connect'; $connect.AutoSize = $true
$close = New-Object Windows.Forms.Button; $close.Text = 'Close tab'; $close.AutoSize = $true
foreach ($pair in @(@('Server:', $server), @('Username (optional):', $user))) {
    $label = New-Object Windows.Forms.Label; $label.Text = $pair[0]; $label.AutoSize = $true; $label.Margin = New-Object Windows.Forms.Padding(3,7,3,0)
    $bar.Controls.Add($label); $bar.Controls.Add($pair[1])
}
$bar.Controls.Add($connect); $bar.Controls.Add($close)
$tabs = New-Object Windows.Forms.TabControl; $tabs.Dock = 'Fill'
$status = New-Object Windows.Forms.StatusStrip
$info = New-Object Windows.Forms.ToolStripStatusLabel; $info.Text = 'Ready. Enter an approved test server.'
[void]$status.Items.Add($info)
$form.Controls.Add($tabs); $form.Controls.Add($bar); $form.Controls.Add($status)
$connect.Add_Click({
    $target = $server.Text.Trim()
    if (-not $target) { return }
    $page = $null; $hostControl = $null
    try {
        $page = New-Object Windows.Forms.TabPage($target)
        $hostControl = New-Object RdpProbeHost
        $hostControl.Dock = 'Fill'
        $page.Tag = $hostControl
        ([ComponentModel.ISupportInitialize]$hostControl).BeginInit()
        $page.Controls.Add($hostControl)
        $tabs.TabPages.Add($page); $tabs.SelectedTab = $page
        ([ComponentModel.ISupportInitialize]$hostControl).EndInit()
        $hostControl.CreateControl()
        $hostControl.OpenSession($target, $user.Text.Trim())
        $info.Text = 'Connection requested: ' + $target
    } catch {
        $message = $_.Exception.ToString()
        if ($page) { $tabs.TabPages.Remove($page); $page.Dispose() }
        if ($hostControl -and -not $hostControl.IsDisposed) { $hostControl.Dispose() }
        $info.Text = 'Connection setup failed.'
        [void][Windows.Forms.MessageBox]::Show($message, 'RDP setup error')
        Write-Warning $message
    }
})
$close.Add_Click({
    $page = $tabs.SelectedTab
    if ($page) {
        try { $page.Tag.DisconnectSession() } catch { Write-Warning $_.Exception.Message }
        $tabs.TabPages.Remove($page); $page.Dispose()
    }
})
$timer = New-Object Windows.Forms.Timer; $timer.Interval = 1000
$timer.Add_Tick({
    $page = $tabs.SelectedTab
    if ($page) { try { $state = switch ($page.Tag.ConnectionState()) { 0 {'Disconnected'} 1 {'Connected'} 2 {'Connecting'} default {'Unknown'} }; $info.Text = $page.Text + ' - ' + $state } catch {} }
})
$form.Add_Shown({ $timer.Start(); $server.Focus() })
$form.Add_FormClosing({ $timer.Stop(); foreach ($page in $tabs.TabPages) { try { $page.Tag.DisconnectSession() } catch {} } })
try { [void]$form.ShowDialog() } finally { $timer.Dispose(); $form.Dispose() }
