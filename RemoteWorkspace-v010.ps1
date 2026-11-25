# Remote Workspace - Phase 1: embedded RDP feasibility test
# Windows PowerShell 5.1, STA. No credentials stored.
$ErrorActionPreference = 'Stop'
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Run with powershell.exe -STA -File Rdp-PoC.ps1' }
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
if (-not ('RdpWorkspaceHostV010' -as [type])) {
    Add-Type -ReferencedAssemblies 'System.Windows.Forms.dll','System.Drawing.dll','Microsoft.CSharp.dll','System.Core.dll' -TypeDefinition @'
using System;
using System.Windows.Forms;
public sealed class RdpWorkspaceHostV010 : AxHost {
    public RdpWorkspaceHostV010() : base("A0C63C30-F08D-4AB4-907C-34905D770C7D") {}
    public void OpenSession(string server, string user) {
        dynamic rdp = GetOcx();
        rdp.Server = server;
        if (!String.IsNullOrWhiteSpace(user)) {
            int separator = user.IndexOf('\\');
            if (separator > 0) {
                rdp.Domain = user.Substring(0, separator);
                rdp.UserName = user.Substring(separator + 1);
            } else { rdp.UserName = user; }
        }
        rdp.DesktopWidth = Math.Max(640, Width);
        rdp.DesktopHeight = Math.Max(480, Height);
        rdp.AdvancedSettings9.EnableCredSspSupport = true;
        rdp.AdvancedSettings9.AuthenticationLevel = 2u;
        rdp.AdvancedSettings9.SmartSizing = true;
        try { rdp.AllowPromptingForCredentials = true; }
        catch (Exception ex) { Console.WriteLine("AllowPromptingForCredentials: " + ex.Message); }
        try { rdp.PromptForCredentials = true; }
        catch (Exception ex) { Console.WriteLine("PromptForCredentials: " + ex.Message); }
        try { rdp.PromptForCredsOnClient = true; }
        catch (Exception ex) { Console.WriteLine("PromptForCredsOnClient: " + ex.Message); }
        try { rdp.AllowCredentialSaving = false; }
        catch (Exception ex) { Console.WriteLine("AllowCredentialSaving: " + ex.Message); }
        rdp.Connect();
    }
    public int ConnectionState() { dynamic rdp = GetOcx(); return (int)rdp.Connected; }
    public void DisconnectSession() { dynamic rdp = GetOcx(); if (rdp.Connected != 0) rdp.Disconnect(); }
}
'@
}

[Windows.Forms.Application]::EnableVisualStyles()
$inventoryPath = Join-Path $PSScriptRoot 'Servers.json'
$settingsDir = Join-Path $env:LOCALAPPDATA 'RemoteWorkspace'
[void][IO.Directory]::CreateDirectory($settingsDir)
$favoritesPath = Join-Path $settingsDir 'Favorites.json'
$script:inventory = @()
$script:favorites = @()
if (Test-Path $inventoryPath) { $script:inventory = @(Get-Content $inventoryPath -Raw | ConvertFrom-Json) }
if (Test-Path $favoritesPath) { $script:favorites = @(Get-Content $favoritesPath -Raw | ConvertFrom-Json) }
function Save-Inventory { ConvertTo-Json -InputObject @($script:inventory) -Depth 5 | Set-Content -LiteralPath $inventoryPath -Encoding UTF8 }
function Save-Favorites { ConvertTo-Json -InputObject @($script:favorites) | Set-Content -LiteralPath $favoritesPath -Encoding UTF8 }
$form = New-Object Windows.Forms.Form
$form.Text = 'Remote Workspace v0.1.0'; $form.Size = New-Object Drawing.Size(1250,850); $form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI',9)
$bar = New-Object Windows.Forms.FlowLayoutPanel
$bar.Dock='Top'; $bar.Height=42; $bar.Padding=New-Object Windows.Forms.Padding(5); $bar.WrapContents=$false; $bar.AutoScroll=$true
function New-Button($text) { $b=New-Object Windows.Forms.Button; $b.Text=$text; $b.AutoSize=$true; $bar.Controls.Add($b); return $b }
$connect=New-Button 'Connect'; $reconnect=New-Button 'Reconnect'; $disconnect=New-Button 'Disconnect'; $close=New-Button 'Close tab'; $favorite=New-Button 'Favorite'; $add=New-Button 'Add server'; $remove=New-Button 'Delete server'
$split=New-Object Windows.Forms.SplitContainer; $split.Dock='Fill'; $split.Size=New-Object Drawing.Size(1200,750); $split.SplitterDistance=280; $split.Panel1MinSize=150; $split.Panel2MinSize=250
$nav=New-Object Windows.Forms.Panel; $nav.Dock='Top'; $nav.Height=105
$search=New-Object Windows.Forms.TextBox; $search.Dock='Top'
$server=New-Object Windows.Forms.TextBox; $server.Dock='Top'
$user=New-Object Windows.Forms.TextBox; $user.Dock='Top'
function Add-Field($caption,$control) { $label=New-Object Windows.Forms.Label; $label.Text=$caption; $label.Dock='Top'; $label.Height=16; $nav.Controls.Add($control); $nav.Controls.Add($label); $label.BringToFront() }
Add-Field 'Username (optional)' $user; Add-Field 'Server / hostname' $server; Add-Field 'Search inventory' $search
$tree=New-Object Windows.Forms.TreeView; $tree.Dock='Fill'; $tree.HideSelection=$false; $tree.ShowNodeToolTips=$true
$split.Panel1.Controls.Add($tree); $split.Panel1.Controls.Add($nav)
$tabs=New-Object Windows.Forms.TabControl; $tabs.Dock='Fill'; $split.Panel2.Controls.Add($tabs)
$status=New-Object Windows.Forms.StatusStrip; $info=New-Object Windows.Forms.ToolStripStatusLabel; $info.Text='Ready - local inventory'; [void]$status.Items.Add($info)
$form.Controls.Add($split); $form.Controls.Add($bar); $form.Controls.Add($status)
function Refresh-Tree {
 $tree.BeginUpdate(); try {
 $tree.Nodes.Clear(); $fav=$tree.Nodes.Add('Favorites'); $root=$tree.Nodes.Add('All servers'); $query=$search.Text.Trim()
 foreach($entry in @($script:inventory | Sort-Object Folder,Name)) {
  if($query -and ("$($entry.Name) $($entry.Hostname) $($entry.Folder)".IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -lt 0)){continue}
  $parent=$root
  foreach($part in @(([string]$entry.Folder -split '[/\\]') | Where-Object {$_})) {
   $folderNode=$null; foreach($n in $parent.Nodes){if($null -eq $n.Tag -and $n.Text -eq $part){$folderNode=$n;break}}
   if($null -eq $folderNode){$folderNode=$parent.Nodes.Add($part)}; $parent=$folderNode
  }
  $node=$parent.Nodes.Add([string]$entry.Name); $node.Tag=$entry; $node.ToolTipText=$entry.Hostname
  if($script:favorites -contains $entry.Hostname){$node=$fav.Nodes.Add([string]$entry.Name);$node.Tag=$entry;$node.ToolTipText=$entry.Hostname}
 }
 $fav.Expand(); $root.Expand(); if($query){$root.ExpandAll()}
 } finally {$tree.EndUpdate()}
}
function Show-Error($message){ [void][Windows.Forms.MessageBox]::Show([string]$message,'Remote Workspace') }
function Open-Session($target,$username,$page=$null) {
 if(-not $target){return}; $control=$null
 try {
  if($null -eq $page){$page=New-Object Windows.Forms.TabPage($target);$tabs.TabPages.Add($page)}
  $tabs.SelectedTab=$page
  $control=New-Object RdpWorkspaceHostV010; $control.Dock='Fill'
  $page.Tag=[pscustomobject]@{HostControl=$control;Target=$target;Username=$username}
  ([ComponentModel.ISupportInitialize]$control).BeginInit();$page.Controls.Add($control);([ComponentModel.ISupportInitialize]$control).EndInit();$control.CreateControl()
  $control.OpenSession($target,$username);$info.Text='Connection requested: '+$target
 } catch {if($page){$tabs.TabPages.Remove($page);$page.Dispose()};if($control -and -not $control.IsDisposed){$control.Dispose()};Show-Error $_.Exception.ToString()}
}
function Stop-Session($page){if($page -and $page.Tag){try{$page.Tag.HostControl.DisconnectSession()}catch{Write-Warning $_.Exception.Message}}}
$connect.Add_Click({Open-Session $server.Text.Trim() $user.Text.Trim()})
$tree.Add_AfterSelect({if($_.Node.Tag){$server.Text=$_.Node.Tag.Hostname}})
$tree.Add_NodeMouseDoubleClick({if($_.Node.Tag){Open-Session $_.Node.Tag.Hostname $user.Text.Trim()}})
$search.Add_TextChanged({Refresh-Tree})
$disconnect.Add_Click({Stop-Session $tabs.SelectedTab})
$close.Add_Click({$page=$tabs.SelectedTab;if($page){Stop-Session $page;$tabs.TabPages.Remove($page);$page.Dispose()}})
$reconnect.Add_Click({$page=$tabs.SelectedTab;if($page -and $page.Tag){$target=$page.Tag.Target;$username=$page.Tag.Username;Stop-Session $page;$old=$page.Tag.HostControl;$page.Controls.Remove($old);$old.Dispose();Open-Session $target $username $page}})
$favorite.Add_Click({$target=$server.Text.Trim();if($target -and @($script:inventory | Where-Object Hostname -eq $target).Count){if($script:favorites -contains $target){$script:favorites=@($script:favorites | Where-Object {$_ -ne $target})}else{$script:favorites+= $target};try{Save-Favorites;Refresh-Tree}catch{Show-Error $_.Exception.Message}}})
$add.Add_Click({
 $dialog=New-Object Windows.Forms.Form;$dialog.Text='Add server';$dialog.Size=New-Object Drawing.Size(400,220);$dialog.StartPosition='CenterParent'
 $fields=@{};$y=12
 foreach($key in @('Name','Hostname','Folder')){$l=New-Object Windows.Forms.Label;$l.Text=$key;$l.Location=New-Object Drawing.Point(10,$y);$l.Width=85;$t=New-Object Windows.Forms.TextBox;$t.Location=New-Object Drawing.Point(100,$y);$t.Width=260;$dialog.Controls.Add($l);$dialog.Controls.Add($t);$fields[$key]=$t;$y+=32}
 $fields.Hostname.Text=$server.Text.Trim();$fields.Name.Text=$server.Text.Trim()
 $ok=New-Object Windows.Forms.Button;$ok.Text='Save';$ok.Location=New-Object Drawing.Point(280,120);$ok.DialogResult='OK';$dialog.Controls.Add($ok);$dialog.AcceptButton=$ok
 try{if($dialog.ShowDialog($form) -eq 'OK'){$target=$fields.Hostname.Text.Trim();$name=$fields.Name.Text.Trim();if(-not $target){Show-Error 'Hostname is required.';return};if(@($script:inventory | Where-Object Hostname -eq $target).Count){Show-Error 'Hostname already exists.';return};if(-not $name){$name=$target};$script:inventory += [pscustomobject]@{Name=$name;Hostname=$target;Folder=$fields.Folder.Text.Trim()};Save-Inventory;Refresh-Tree}}catch{Show-Error $_.Exception.Message}finally{$dialog.Dispose()}
})
$remove.Add_Click({$entry=$tree.SelectedNode;if($entry -and $entry.Tag){$target=$entry.Tag.Hostname;if([Windows.Forms.MessageBox]::Show("Delete $target from local inventory?",'Confirm','YesNo') -eq 'Yes'){$script:inventory=@($script:inventory | Where-Object Hostname -ne $target);$script:favorites=@($script:favorites | Where-Object {$_ -ne $target});try{Save-Inventory;Save-Favorites;Refresh-Tree}catch{Show-Error $_.Exception.Message}}}})
$menu=New-Object Windows.Forms.ContextMenuStrip
foreach($b in @($connect,$reconnect,$disconnect,$favorite,$remove)){ $item=New-Object Windows.Forms.ToolStripMenuItem($b.Text);$item.Tag=$b;$item.Add_Click({$this.Tag.PerformClick()});[void]$menu.Items.Add($item) }
$tree.ContextMenuStrip=$menu;$tree.Add_NodeMouseClick({if($_.Button -eq 'Right'){$tree.SelectedNode=$_.Node}})
$timer=New-Object Windows.Forms.Timer;$timer.Interval=1000;$timer.Add_Tick({$page=$tabs.SelectedTab;if($page -and $page.Tag){try{$state=switch($page.Tag.HostControl.ConnectionState()){0{'Disconnected'} 1{'Connected'} 2{'Connecting'} default{'Unknown'}};$info.Text=$page.Text+' - '+$state+' | Local inventory'}catch{}}else{$info.Text='Ready - local inventory'}})
$form.Add_Shown({Refresh-Tree;$timer.Start()});$form.Add_FormClosing({$timer.Stop();foreach($page in $tabs.TabPages){Stop-Session $page}})
try{[void]$form.ShowDialog()}finally{$timer.Dispose();$form.Dispose()}
