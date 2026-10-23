Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverDir = Join-Path $root 'server'
$script:activeServerDir = $serverDir
$pluginsDir = Join-Path $serverDir 'plugins'
$modsDir = Join-Path $serverDir 'mods'
foreach ($d in @($serverDir, $pluginsDir, $modsDir)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
$defaultEula = Join-Path $serverDir 'eula.txt'
if (-not (Test-Path $defaultEula)) {
    [IO.File]::WriteAllText($defaultEula, "# Read https://aka.ms/MinecraftEULA before accepting." + [Environment]::NewLine + 'eula=false' + [Environment]::NewLine)
}

$form = New-Object Windows.Forms.Form
$form.Text = 'TycoonConsole'
$form.Size = New-Object Drawing.Size(780, 650)
$form.MinimumSize = New-Object Drawing.Size(780, 650)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [Drawing.Color]::FromArgb(20, 22, 29)
$form.ForeColor = [Drawing.Color]::Gainsboro
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
$script:serverProcess = $null

function Label($t, $x, $y, $w, $h, $size = 10) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $t
    $l.Location = New-Object Drawing.Point($x, $y)
    $l.Size = New-Object Drawing.Size($w, $h)
    $l.ForeColor = [Drawing.Color]::Gainsboro
    $l.Font = New-Object Drawing.Font('Segoe UI', $size)
    $form.Controls.Add($l)
    return $l
}
function Button($t, $x, $y, $w, $h, $a) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $t
    $b.Location = New-Object Drawing.Point($x, $y)
    $b.Size = New-Object Drawing.Size($w, $h)
    $b.FlatStyle = 'Flat'
    $b.BackColor = [Drawing.Color]::FromArgb(42, 47, 60)
    $b.ForeColor = 'White'
    $b.Add_Click($a)
    $form.Controls.Add($b)
    return $b
}
function Log($s) {
    $log.AppendText(('[' + (Get-Date -Format HH:mm:ss) + '] ' + $s + [Environment]::NewLine))
}
function Refresh-Network {
    $items = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike '127.*' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.InterfaceAlias -notmatch 'Loopback|Virtual|WSL|Docker|Hyper-V'
        }
    $chosen = $items | Select-Object -First 1
    $lan.Text = 'LAN IP: ' + $(if ($chosen) { $chosen.IPAddress } else { 'Not detected' })
    $p = '25565'
    $prop = Join-Path $script:activeServerDir 'server.properties'
    if (Test-Path $prop) {
        $line = Get-Content -LiteralPath $prop | Where-Object { $_ -match '^server-port=\d+$' } | Select-Object -First 1
        if ($line -match '^server-port=(\d+)$') { $p = $Matches[1] }
    }
    $port.Text = 'Server port: ' + $p
    try {
        $pub.Text = 'Public IP (detected): ' + (Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 4).ToString().Trim()
    } catch {
        $pub.Text = 'Public IP: unavailable (check internet)'
    }
    Log 'Network refreshed. A detected public IP does not guarantee inbound reachability.'
}
function Save-ConfiguredJar($path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    [IO.File]::WriteAllText((Join-Path $root 'server-jar.txt'), $path.Trim())
}
function Pick-Jar {
    $jarConfig = Join-Path $root 'server-jar.txt'
    if (Test-Path -LiteralPath $jarConfig) {
        $savedJar = (Get-Content -LiteralPath $jarConfig -Raw).Trim()
        if ($savedJar -and (Test-Path -LiteralPath $savedJar -PathType Leaf) -and ([IO.Path]::GetExtension($savedJar) -ieq '.jar')) {
            return $savedJar
        }
    }

    # Automatically find a server JAR in the app folder or its default server folder.
    $searchDirs = @($script:activeServerDir, $root) | Select-Object -Unique
    $jars = @()
    foreach ($dir in $searchDirs) {
        if (Test-Path -LiteralPath $dir -PathType Container) {
            $jars += @(Get-ChildItem -LiteralPath $dir -Filter '*.jar' -File -ErrorAction SilentlyContinue)
        }
    }
    $jars = @($jars | Sort-Object -Property FullName -Unique)
    if ($jars.Count -eq 1) {
        Save-ConfiguredJar $jars[0].FullName
        return $jars[0].FullName
    }

    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Title = 'Select your Minecraft SERVER JAR (Paper server jar, not a client/mod jar)'
    $dlg.Filter = 'Java archives (*.jar)|*.jar'
    $dlg.InitialDirectory = $script:activeServerDir
    if ($dlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        Save-ConfiguredJar $dlg.FileName
        return $dlg.FileName
    }
    return $null
}
function Backup-Once($path) {
    if (Test-Path -LiteralPath $path) {
        $backup = $path + '.tycoonconsole.bak'
        if (-not (Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $path -Destination $backup
        }
    }
}
function Apply-MinehutSettings {
    $prop = Join-Path $script:activeServerDir 'server.properties'
    if (Test-Path -LiteralPath $prop) {
        Backup-Once $prop
        $raw = Get-Content -LiteralPath $prop -Raw
        if ($raw -match '(?m)^enforce-secure-profile=') {
            $raw = [regex]::Replace($raw, '(?m)^enforce-secure-profile=.*$', 'enforce-secure-profile=false')
        } else {
            $raw = $raw.TrimEnd() + [Environment]::NewLine + 'enforce-secure-profile=false' + [Environment]::NewLine
        }
        [IO.File]::WriteAllText($prop, $raw)
        Log 'Minehut mode set enforce-secure-profile=false; original backed up if a backup did not already exist.'
    } else {
        Log 'server.properties does not exist yet; start the server once without Minehut mode, stop it, then enable Minehut mode.'
    }

    $paper = Join-Path $script:activeServerDir 'config\paper-global.yml'
    if (Test-Path -LiteralPath $paper) {
        Backup-Once $paper
        $raw = Get-Content -LiteralPath $paper -Raw
        if ($raw -match '(?m)^[ \t]*proxy-protocol:[ \t]*(true|false)[ \t]*$') {
            $raw = [regex]::Replace($raw, '(?m)^([ \t]*)proxy-protocol:[ \t]*(true|false)[ \t]*$', '$1proxy-protocol: true')
        } elseif ($raw -match '(?m)^proxies:[ \t]*$') {
            $raw = [regex]::Replace($raw, '(?m)^proxies:[ \t]*$', ('proxies:' + [Environment]::NewLine + '  proxy-protocol: true'), 1)
        } else {
            $raw = $raw.TrimEnd() + [Environment]::NewLine + 'proxies:' + [Environment]::NewLine + '  proxy-protocol: true' + [Environment]::NewLine
        }
        [IO.File]::WriteAllText($paper, $raw)
        Log 'Minehut mode enabled Paper proxy protocol; original backed up if a backup did not already exist.'
    } else {
        Log 'paper-global.yml not found yet. Start Paper once, stop it, then enable Minehut mode again.'
    }
}

Label 'TYCOON CONSOLE' 24 18 440 42 22 | Out-Null
Label 'Self-hosted Minecraft server control' 26 57 500 24 10 | Out-Null
$lan = Label 'LAN IP: detecting...' 28 102 710 25
$pub = Label 'Public IP: checking...' 28 130 710 25
$port = Label 'Server port: 25565 (default)' 28 158 710 25
$status = Label 'Status: stopped' 28 194 710 25
$log = New-Object Windows.Forms.TextBox
$log.Location = New-Object Drawing.Point(28, 230)
$log.Size = New-Object Drawing.Size(710, 180)
$log.Multiline = $true
$log.ReadOnly = $true
$log.ScrollBars = 'Vertical'
$log.BackColor = [Drawing.Color]::FromArgb(12, 14, 19)
$log.ForeColor = [Drawing.Color]::FromArgb(180, 220, 190)
$log.Font = New-Object Drawing.Font('Consolas', 9)
$form.Controls.Add($log)

$minehut = New-Object Windows.Forms.CheckBox
$minehut.Text = 'Minehut External Hosting mode (standalone Paper only; not TCPShield)'
$minehut.Location = New-Object Drawing.Point(28, 416)
$minehut.Size = New-Object Drawing.Size(700, 26)
$minehut.ForeColor = [Drawing.Color]::FromArgb(255, 205, 125)
$minehut.BackColor = $form.BackColor
$form.Controls.Add($minehut)

Button 'Start Server' 28 454 150 40 {
    if ($script:serverProcess -and -not $script:serverProcess.HasExited) {
        [Windows.Forms.MessageBox]::Show('The server process is already running.') | Out-Null
        return
    }

    $jar = Pick-Jar
    if (-not $jar) {
        Log 'No server JAR selected. Put a Paper server .jar in the app folder or server folder, or select one when prompted.'
        return
    }
    if (-not (Test-Path -LiteralPath $jar -PathType Leaf)) {
        Remove-Item -LiteralPath (Join-Path $root 'server-jar.txt') -Force -ErrorAction SilentlyContinue
        Log 'The saved server JAR path no longer exists. Removed the saved selection; click Start Server to choose a valid server JAR.'
        [Windows.Forms.MessageBox]::Show('The previously selected server JAR could not be found. It has been cleared. Click Start Server again and select your Paper server .jar.', 'Server JAR not found') | Out-Null
        return
    }

    $script:activeServerDir = Split-Path -Parent $jar
    $eula = Join-Path $script:activeServerDir 'eula.txt'
    if (-not (Test-Path -LiteralPath $eula)) {
        [IO.File]::WriteAllText($eula, "# Read https://aka.ms/MinecraftEULA before accepting." + [Environment]::NewLine + 'eula=false' + [Environment]::NewLine)
    }
    if ((Get-Content -LiteralPath $eula -Raw) -notmatch '(?m)^eula=true\s*$') {
        [Windows.Forms.MessageBox]::Show(
            ('The EULA file is here:' + [Environment]::NewLine + $eula + [Environment]::NewLine + [Environment]::NewLine + 'Read https://aka.ms/MinecraftEULA. If you agree, edit eula=false to eula=true, save the file, then click Start Server again.'),
            'EULA required'
        ) | Out-Null
        Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $eula + '"')
        Log ('Start blocked until EULA is manually accepted: ' + $eula)
        return
    }

    if ($minehut.Checked) { Apply-MinehutSettings }
    $jvm = @('-Xms2G', '-Xmx6G')
    if ($minehut.Checked) {
        $jvm += @(
            '-Dminecraft.api.services.host=https://api.minecraftservices.com/',
            '-Dminecraft.api.auth.host=https://authserver.mojang.com/',
            '-Dminecraft.api.account.host=https://api.mojang.com/',
            '-Dminecraft.api.profiles.host=https://api.mojang.com/',
            '-Dminecraft.api.session.host=https://api.minehut.com/mitm/proxy'
        )
        Log 'Minehut authentication JVM flags enabled. Use only for standalone Paper without TCPShield, as directed by Minehut.'
    }

    $javaCommand = Get-Command 'java.exe' -ErrorAction SilentlyContinue
    if (-not $javaCommand) { $javaCommand = Get-Command 'java' -ErrorAction SilentlyContinue }
    if (-not $javaCommand) {
        Log 'Start failed: Java was not found on PATH. Install Java 21, then reopen TycoonConsole.'
        [Windows.Forms.MessageBox]::Show('Java was not found. Install Java 21 and make sure java.exe is available on PATH, then reopen TycoonConsole.', 'Java required') | Out-Null
        return
    }

    $argsText = ($jvm + @('-jar', ('"' + $jar + '"'), 'nogui')) -join ' '
    try {
        $script:serverProcess = Start-Process -FilePath $javaCommand.Source -ArgumentList $argsText -WorkingDirectory $script:activeServerDir -PassThru
        $status.Text = 'Status: running (PID ' + $script:serverProcess.Id + ')'
        $status.ForeColor = 'LightGreen'
        Log 'Server process launched with 6 GB maximum heap. Use the server console and type stop for safe shutdown.'
        Refresh-Network
    } catch {
        Log ('Start failed: ' + $_.Exception.Message + '. Confirm Java is installed and on PATH.')
    }
} | Out-Null

Button 'Stop Server' 190 454 130 40 {
    if ($script:serverProcess -and -not $script:serverProcess.HasExited) {
        [Windows.Forms.MessageBox]::Show('For safe shutdown, type stop in the server console. Force-closing may corrupt world data.') | Out-Null
    } else {
        Log 'No server process running.'
    }
} | Out-Null
Button 'Server Folder' 332 454 120 40 { Start-Process explorer.exe $script:activeServerDir } | Out-Null
Button 'Plugins Folder' 464 454 120 40 {
    $p = Join-Path $script:activeServerDir 'plugins'
    New-Item -ItemType Directory -Force -Path $p | Out-Null
    Start-Process explorer.exe $p
} | Out-Null
Button 'Mods Folder' 596 454 118 40 {
    $p = Join-Path $script:activeServerDir 'mods'
    New-Item -ItemType Directory -Force -Path $p | Out-Null
    Start-Process explorer.exe $p
} | Out-Null
Button 'Refresh IP / Port' 28 504 150 34 { Refresh-Network } | Out-Null
Button 'Check for Updates' 190 504 170 34 {
    try {
        $r = Invoke-RestMethod 'https://api.github.com/repos/Paralied/TycoonConsole/releases/latest' -Headers @{ 'User-Agent' = 'TycoonConsole' } -TimeoutSec 8
        $asset = $r.assets | Where-Object { $_.name -eq 'TycoonConsole-Source.zip' } | Select-Object -First 1
        if (-not $r.tag_name -or -not $asset) {
            [Windows.Forms.MessageBox]::Show('No installable release package was found yet. Push a commit to main and wait for the GitHub Actions release workflow to finish.', 'Update check') | Out-Null
            return
        }
        $choice = [Windows.Forms.MessageBox]::Show(
            ('Install TycoonConsole ' + $r.tag_name + '?' + [Environment]::NewLine + 'The console will close, back up the current launcher files, install the release source, then reopen.'),
            'TycoonConsole updater',
            [Windows.Forms.MessageBoxButtons]::YesNo
        )
        if ($choice -ne [Windows.Forms.DialogResult]::Yes) { return }

        $temp = Join-Path $env:TEMP ('TycoonConsole-update-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        $zip = Join-Path $temp 'update.zip'
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -TimeoutSec 60
        Expand-Archive -LiteralPath $zip -DestinationPath $temp -Force
        if (-not (Test-Path (Join-Path $temp 'TycoonConsole.ps1')) -or -not (Test-Path (Join-Path $temp 'Start-TycoonConsole.bat'))) {
            throw 'The release archive did not contain the expected launcher files.'
        }

        $helper = Join-Path $temp 'apply-update.cmd'
        $scriptBackup = Join-Path $root 'TycoonConsole.ps1.tycoonconsole.previous'
        $launcherBackup = Join-Path $root 'Start-TycoonConsole.bat.tycoonconsole.previous'
        $lines = @(
            '@echo off',
            'setlocal',
            'timeout /t 3 /nobreak >nul',
            'if exist "' + (Join-Path $root 'TycoonConsole.ps1') + '" copy /y "' + (Join-Path $root 'TycoonConsole.ps1') + '" "' + $scriptBackup + '" >nul',
            'if exist "' + (Join-Path $root 'Start-TycoonConsole.bat') + '" copy /y "' + (Join-Path $root 'Start-TycoonConsole.bat') + '" "' + $launcherBackup + '" >nul',
            'copy /y "' + (Join-Path $temp 'TycoonConsole.ps1') + '" "' + (Join-Path $root 'TycoonConsole.ps1') + '" >nul',
            'if errorlevel 1 goto failed',
            'copy /y "' + (Join-Path $temp 'Start-TycoonConsole.bat') + '" "' + (Join-Path $root 'Start-TycoonConsole.bat') + '" >nul',
            'if errorlevel 1 goto failed',
            'start "" "' + (Join-Path $root 'Start-TycoonConsole.bat') + '"',
            'exit /b 0',
            ':failed',
            'echo Update failed. Source files remain in "' + $temp + '".',
            'pause'
        )
        [IO.File]::WriteAllLines($helper, $lines, [Text.Encoding]::ASCII)
        Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', ('"' + $helper + '"')) -WorkingDirectory $root
        Log ('Update ' + $r.tag_name + ' downloaded; closing console so the updater can replace launcher files.')
        $form.Close()
    } catch {
        [Windows.Forms.MessageBox]::Show(('Update failed: ' + $_.Exception.Message), 'TycoonConsole updater') | Out-Null
        Log ('Update failed: ' + $_.Exception.Message)
    }
} | Out-Null
Button 'Open GitHub' 372 504 130 34 { Start-Process 'https://github.com/Paralied/TycoonConsole' } | Out-Null
Button 'Open EULA' 512 504 110 34 {
    $ep = Join-Path $script:activeServerDir 'eula.txt'
    if (-not (Test-Path -LiteralPath $ep)) {
        [IO.File]::WriteAllText($ep, "# Read https://aka.ms/MinecraftEULA before accepting." + [Environment]::NewLine + 'eula=false' + [Environment]::NewLine)
    }
    Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $ep + '"')
} | Out-Null
Button 'Change Server JAR' 28 584 170 34 {
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Title = 'Choose Minecraft SERVER JAR'
    $dlg.Filter = 'Java archives (*.jar)|*.jar'
    $dlg.InitialDirectory = $script:activeServerDir
    if ($dlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        Save-ConfiguredJar $dlg.FileName
        $script:activeServerDir = Split-Path -Parent $dlg.FileName
        Log ('Saved server JAR: ' + $dlg.FileName)
        Refresh-Network
        [Windows.Forms.MessageBox]::Show('Server JAR saved. You will not need to select it again unless you move or replace the file.', 'Server JAR saved') | Out-Null
    }
} | Out-Null
Label 'Paper plugins go in plugins\. Fabric/Forge mods need a compatible loader; Paper cannot load them.' 28 548 710 28 8 | Out-Null

Refresh-Network
Log 'Ready. For 32 GB system RAM and 10–20 players, 6 GB maximum heap is a reasonable baseline.'
Log 'Minehut mode is opt-in and only for standalone Paper; it edits settings with backups. Verify reachability separately.'
[void]$form.ShowDialog()
