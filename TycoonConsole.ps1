Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverDir = Join-Path $root 'server'
$pluginsDir = Join-Path $serverDir 'plugins'
$modsDir = Join-Path $serverDir 'mods'
foreach ($d in @($serverDir,$pluginsDir,$modsDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
$form = New-Object Windows.Forms.Form
$form.Text = 'TycoonConsole'; $form.Size = New-Object Drawing.Size(780,650); $form.MinimumSize=New-Object Drawing.Size(780,650); $form.StartPosition='CenterScreen'
$form.BackColor=[Drawing.Color]::FromArgb(20,22,29); $form.ForeColor=[Drawing.Color]::Gainsboro
$form.Font=New-Object Drawing.Font('Segoe UI',10)
$script:serverProcess=$null
function Label($t,$x,$y,$w,$h,$size=10) { $l=New-Object Windows.Forms.Label; $l.Text=$t; $l.Location=New-Object Drawing.Point($x,$y); $l.Size=New-Object Drawing.Size($w,$h); $l.ForeColor=[Drawing.Color]::Gainsboro; $l.Font=New-Object Drawing.Font('Segoe UI',$size); $form.Controls.Add($l); return $l }
function Button($t,$x,$y,$w,$h,$a) { $b=New-Object Windows.Forms.Button; $b.Text=$t; $b.Location=New-Object Drawing.Point($x,$y); $b.Size=New-Object Drawing.Size($w,$h); $b.FlatStyle='Flat'; $b.BackColor=[Drawing.Color]::FromArgb(42,47,60); $b.ForeColor='White'; $b.Add_Click($a); $form.Controls.Add($b); return $b }
Label 'TYCOON CONSOLE' 24 18 440 42 22 | Out-Null
Label 'Self-hosted Minecraft server control' 26 57 500 24 10 | Out-Null
$lan=Label 'LAN IP: detecting...' 28 102 710 25
$pub=Label 'Public IP: checking...' 28 130 710 25
$port=Label 'Server port: 25565 (default)' 28 158 710 25
$status=Label 'Status: stopped' 28 194 710 25
$log=New-Object Windows.Forms.TextBox; $log.Location=New-Object Drawing.Point(28,230); $log.Size=New-Object Drawing.Size(710,180); $log.Multiline=$true; $log.ReadOnly=$true; $log.ScrollBars='Vertical'; $log.BackColor=[Drawing.Color]::FromArgb(12,14,19); $log.ForeColor=[Drawing.Color]::FromArgb(180,220,190); $log.Font=New-Object Drawing.Font('Consolas',9); $form.Controls.Add($log)
function Log($s) { $log.AppendText(('['+(Get-Date -Format HH:mm:ss)+'] '+$s+[Environment]::NewLine)) }
$minehut=New-Object Windows.Forms.CheckBox
$minehut.Text='Minehut External Hosting mode (standalone Paper only; not TCPShield)'
$minehut.Location=New-Object Drawing.Point(28,416); $minehut.Size=New-Object Drawing.Size(700,26); $minehut.ForeColor=[Drawing.Color]::FromArgb(255,205,125); $minehut.BackColor=$form.BackColor
$form.Controls.Add($minehut)
function Refresh-Network {
  $items=Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.InterfaceAlias -notmatch 'Loopback|Virtual|WSL|Docker|Hyper-V' }
  $chosen=$items | Select-Object -First 1
  $lan.Text='LAN IP: '+$(if($chosen){$chosen.IPAddress}else{'Not detected'})
  $p='25565'; $prop=Join-Path $serverDir 'server.properties'
  if(Test-Path $prop){$line=Get-Content $prop | Where-Object {$_ -match '^server-port=\d+$'} | Select-Object -First 1; if($line -match '^server-port=(\d+)$'){$p=$Matches[1]}}
  $port.Text='Server port: '+$p
  try{$pub.Text='Public IP (detected): '+(Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 4).ToString().Trim()}catch{$pub.Text='Public IP: unavailable (check internet)'}
  Log 'Network refreshed. Detected public IP does not guarantee inbound reachability.'
}
function Pick-Jar {
  $jars=Get-ChildItem $serverDir -Filter '*.jar' -File -ErrorAction SilentlyContinue
  if($jars.Count -eq 1){return $jars[0].FullName}
  $dlg=New-Object Windows.Forms.OpenFileDialog; $dlg.Title='Select Minecraft server JAR'; $dlg.Filter='Java archives (*.jar)|*.jar'; $dlg.InitialDirectory=$serverDir
  if($dlg.ShowDialog() -eq 'OK'){return $dlg.FileName}; return $null
}
function Backup-Once($path) {
  if(Test-Path $path) {
    $backup=$path+'.tycoonconsole.bak'
    if(-not(Test-Path $backup)){Copy-Item -LiteralPath $path -Destination $backup}
  }
}
function Apply-MinehutSettings {
  $prop=Join-Path $serverDir 'server.properties'
  if(Test-Path $prop) {
    Backup-Once $prop
    $raw=Get-Content -LiteralPath $prop -Raw
    if($raw -match '(?m)^enforce-secure-profile=') {$raw=[regex]::Replace($raw,'(?m)^enforce-secure-profile=.*$','enforce-secure-profile=false')}
    else {$raw=$raw.TrimEnd()+[Environment]::NewLine+'enforce-secure-profile=false'+[Environment]::NewLine}
    [IO.File]::WriteAllText($prop,$raw)
    Log 'Minehut mode set enforce-secure-profile=false; backup saved beside original if not already present.'
  } else { Log 'server.properties does not exist yet; secure-profile setting will need to be applied after first server generation.' }
  $paper=Join-Path $serverDir 'config\paper-global.yml'
  if(Test-Path $paper) {
    Backup-Once $paper
    $raw=Get-Content -LiteralPath $paper -Raw
    if($raw -match '(?m)^\s*proxy-protocol:\s*(true|false)\s*$') {
      $raw=[regex]::Replace($raw,'(?m)^(\s*)proxy-protocol:\s*(true|false)\s*$','$1proxy-protocol: true')
    } elseif($raw -match '(?m)^proxies:\s*$') {
      $raw=[regex]::Replace($raw,'(?m)^proxies:\s*$','proxies:'+ [Environment]::NewLine+'  proxy-protocol: true',1)
    } else {
      $raw=$raw.TrimEnd()+[Environment]::NewLine+'proxies:'+ [Environment]::NewLine+'  proxy-protocol: true'+[Environment]::NewLine
    }
    [IO.File]::WriteAllText($paper,$raw)
    Log 'Minehut mode enabled Paper proxy protocol; backup saved beside original if not already present.'
  } else { Log 'paper-global.yml not found yet. Start Paper once, stop it, then enable Minehut mode again to apply proxy protocol.' }
}
Button 'Start Server' 28 454 150 40 {
  if($script:serverProcess -and -not $script:serverProcess.HasExited){[Windows.Forms.MessageBox]::Show('The server process is already running.')|Out-Null;return}
  $jar=Pick-Jar; if(-not $jar){Log 'No server JAR selected.';return}
  $eula=Join-Path (Split-Path $jar -Parent) 'eula.txt'
  if(-not(Test-Path $eula)){[IO.File]::WriteAllText($eula,"# Read https://aka.ms/MinecraftEULA before accepting."+[Environment]::NewLine+'eula=false'+[Environment]::NewLine)}
  if((Get-Content $eula -Raw) -notmatch '(?m)^eula=true\s*$'){[Windows.Forms.MessageBox]::Show('Read the Minecraft EULA. If you agree, set eula=true in the server\eula.txt file and click Start again.','EULA required')|Out-Null;Log 'Start blocked until EULA is accepted.';return}
  if($minehut.Checked) { Apply-MinehutSettings }
  $jvm=@('-Xms2G','-Xmx6G')
  if($minehut.Checked) {
    $jvm+=@('-Dminecraft.api.services.host=https://api.minecraftservices.com/','-Dminecraft.api.auth.host=https://authserver.mojang.com/','-Dminecraft.api.account.host=https://api.mojang.com/','-Dminecraft.api.profiles.host=https://api.mojang.com/','-Dminecraft.api.session.host=https://api.minehut.com/mitm/proxy')
    Log 'Minehut authentication JVM flags enabled. Use only for standalone Paper without TCPShield, as directed by Minehut.'
  }
  $argsText=($jvm+@('-jar',('"'+$jar+'"'),'nogui')) -join ' '
  try{$script:serverProcess=Start-Process -FilePath 'java' -ArgumentList $argsText -WorkingDirectory (Split-Path $jar -Parent) -PassThru; $status.Text='Status: running (PID '+$script:serverProcess.Id+')';$status.ForeColor='LightGreen';Log 'Server process launched with 6 GB maximum heap. Use its console window and type stop for safe shutdown.'}catch{Log ('Start failed: '+$_.Exception.Message+'. Confirm Java is installed and on PATH.')}
} | Out-Null
Button 'Stop Server' 190 454 130 40 {if($script:serverProcess -and -not $script:serverProcess.HasExited){[Windows.Forms.MessageBox]::Show('For safe shutdown, type stop in the server console. Force-closing may corrupt world data.')|Out-Null}else{Log 'No server process running.'}}|Out-Null
Button 'Server Folder' 332 454 120 40 {Start-Process explorer.exe $serverDir}|Out-Null
Button 'Plugins Folder' 464 454 120 40 {Start-Process explorer.exe $pluginsDir}|Out-Null
Button 'Mods Folder' 596 454 118 40 {Start-Process explorer.exe $modsDir}|Out-Null
Button 'Refresh IP / Port' 28 504 150 34 {Refresh-Network}|Out-Null
Button 'Check for Updates' 190 504 170 34 {
 try{$r=Invoke-RestMethod 'https://api.github.com/repos/Paralied/TycoonConsole/releases/latest' -Headers @{'User-Agent'='TycoonConsole'} -TimeoutSec 8;if($r.tag_name){$a=[Windows.Forms.MessageBox]::Show(('Latest release: '+$r.tag_name+[Environment]::NewLine+$r.html_url+[Environment]::NewLine+'Open release page? Automatic replacement is not implemented in this source scaffold.'),'Update check',[Windows.Forms.MessageBoxButtons]::YesNo);if($a -eq [Windows.Forms.DialogResult]::Yes){Start-Process $r.html_url}}else{[Windows.Forms.MessageBox]::Show('No published release found yet.')|Out-Null}}catch{[Windows.Forms.MessageBox]::Show('Could not check GitHub Releases. Try again later.')|Out-Null}
}|Out-Null
Button 'Open GitHub' 372 504 130 34 {Start-Process 'https://github.com/Paralied/TycoonConsole'}|Out-Null
Label 'Paper plugins go in plugins\. Fabric/Forge mods need a compatible loader; Paper cannot load them.' 28 548 710 28 8 | Out-Null
Refresh-Network
Log 'Ready. For 32 GB system RAM and 10–20 players, 6 GB maximum heap is a reasonable baseline.'
Log 'Minehut mode is opt-in and only for standalone Paper; it edits settings with backups. Verify reachability separately.'
[void]$form.ShowDialog()
