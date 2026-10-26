#Requires -Version 5.1
<#
.SYNOPSIS
  Share Claude Code state with NixOS via the dual-boot NTFS drive.

.DESCRIPTION
  Generated from the NixOS repo (modules/features/software/claudeSync) and
  copied to <shared>\_sync\ on every nixos-rebuild. Safe to re-run any time.

  - Turns %USERPROFILE%\.claude\{projects,skills,agents,...} into junctions
    pointing at the shared store, after moving existing data into it.
  - Merges shared plugin/marketplace settings into settings.json.
  - Disables Fast Startup, which otherwise leaves NTFS "dirty" so NixOS
    mounts it read-only or not at all.

  Run once per Windows user:
    powershell -ExecutionPolicy Bypass -File E:\.claude-shared\_sync\bootstrap.ps1
  Run as Administrator once so Fast Startup can be switched off.

.PARAMETER Uninstall
  Remove the junctions and copy the shared data back into local folders.
  The shared store itself is left untouched.
#>
[CmdletBinding()]
param(
  [string]$SharedRoot,
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 can leave $PSScriptRoot empty (notably while it is
# evaluating param defaults), so resolve the script's folder ourselves.
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $SharedRoot) { $SharedRoot = Split-Path -Parent $ScriptDir }
$ClaudeDir = Join-Path $env:USERPROFILE '.claude'
$Manifest  = Get-Content -Raw -LiteralPath (Join-Path $ScriptDir 'shared.json') | ConvertFrom-Json
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = Join-Path $ClaudeDir "backups\pre-shared-$Stamp"

# Every (local folder -> shared folder) pair this script manages.
$Links = @()
foreach ($name in @('projects') + @($Manifest.linkDirs) + @($Manifest.perEntryDirs)) {
  $Links += [PSCustomObject]@{ Local = (Join-Path $ClaudeDir $name); Target = (Join-Path $SharedRoot $name); LocalWins = $false }
}
foreach ($p in $Manifest.homeLinkDirs.PSObject.Properties) {   # e.g. .claude-mem -> claude-mem
  # A database can't be merged file by file, so Windows' copy wins the first move.
  $Links += [PSCustomObject]@{ Local = (Join-Path $env:USERPROFILE $p.Name); Target = (Join-Path $SharedRoot $p.Value); LocalWins = $true }
}

function Say($msg) { Write-Host "claude-shared: $msg" }

function Test-Junction([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  return [bool]($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))
}

# Removes ONLY the link. Never Remove-Item -Recurse on a junction: Windows
# PowerShell 5.1 follows it and deletes the shared data on the other side.
function Remove-Junction([string]$Path) {
  cmd /c rmdir "$Path" | Out-Null
  if (Test-Path -LiteralPath $Path) { throw "could not remove junction $Path" }
}

# Moves files from $Src into $Dst without overwriting anything there.
# robocopy exit codes 0-7 are success.
function Move-Merge([string]$Src, [string]$Dst) {
  New-Item -ItemType Directory -Force -Path $Dst | Out-Null
  robocopy $Src $Dst /E /MOVE /XC /XN /XO /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE) moving $Src -> $Dst" }
  if (Test-Path -LiteralPath $Src) {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $rest = Join-Path $BackupDir (Split-Path -Leaf $Src)
    Move-Item -LiteralPath $Src -Destination $rest
    Say "kept conflicting leftovers of $Src in $rest"
  }
}

function Install-Link([string]$local, [string]$target, [bool]$LocalWins) {
  if (Test-Junction $local) {
    if (@((Get-Item -LiteralPath $local -Force).Target) -contains $target) { return }
    Remove-Junction $local
  } elseif (Test-Path -LiteralPath $local) {
    if ($LocalWins -and (Test-Path -LiteralPath $target)) {
      $aside = "$target.linux-$Stamp"
      Move-Item -LiteralPath $target -Destination $aside
      Say "set aside the NixOS copy of $target as $aside"
    }
    Move-Merge $local $target
  }
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  New-Item -ItemType Junction -Path $local -Target $target | Out-Null
  Say "$local -> $target"
}

function Uninstall-Link([string]$local, [string]$target) {
  if (-not (Test-Junction $local)) { return }
  Remove-Junction $local
  New-Item -ItemType Directory -Force -Path $local | Out-Null
  robocopy $target $local /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  Say "unlinked $local (copied shared data back)"
}

function Merge-Settings {
  $path = Join-Path $ClaudeDir 'settings.json'
  $data = New-Object PSObject
  if (Test-Path -LiteralPath $path) {
    Copy-Item -LiteralPath $path -Destination "$path.pre-shared-$Stamp"
    $data = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  }
  foreach ($block in @($Manifest.settings, $Manifest.windowsSettings)) {
    if ($block) { Merge-Object $data $block }
  }
  Register-Hook $data (Join-Path $ScriptDir 'hook.ps1')
  Write-Json $path $data
  Say "merged shared settings into $path"
}

# SessionStart hook: keeps Windows and NixOS in step however claude starts
# (claude, headroom wrap claude, IDE). Also runs on SessionEnd, so a skill
# installed during the session (npx skills leaves a junction to C: in the
# shared folder) is turned into real files before NixOS next boots.
# Replaces any earlier copy of itself.
function Register-Hook($Data, [string]$HookScript) {
  $script = $HookScript -replace '\\', '/'
  $command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$script`""
  if (-not $Data.PSObject.Properties['hooks']) {
    $Data | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object PSObject)
  }
  foreach ($event in @('SessionStart', 'SessionEnd')) {
    $groups = @()
    if ($Data.hooks.PSObject.Properties[$event]) { $groups = @($Data.hooks.$event) }
    $groups = @($groups | Where-Object { -not (@($_.hooks) | Where-Object { [string]$_.command -like '*_sync/hook.ps1*' }) })
    $groups += [PSCustomObject]@{ hooks = @([PSCustomObject]@{ type = 'command'; command = $command; timeout = 30 }) }
    $Data.hooks | Add-Member -Force -NotePropertyName $event -NotePropertyValue $groups
  }
}

# Shallow-merge $Src into $Dst: nested objects merge one level, rest replaces.
function Merge-Object($Dst, $Src) {
  foreach ($prop in $Src.PSObject.Properties) {
    if ($prop.Name.StartsWith('_')) { continue }
    $current = $Dst.PSObject.Properties[$prop.Name]
    if ($prop.Value -is [PSCustomObject] -and $current -and $current.Value -is [PSCustomObject]) {
      foreach ($sub in $prop.Value.PSObject.Properties) {
        $current.Value | Add-Member -Force -NotePropertyName $sub.Name -NotePropertyValue $sub.Value
      }
    } else {
      $Dst | Add-Member -Force -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
    }
  }
}

function Write-Json([string]$Path, $Data) {
  $json = ConvertTo-Json -InputObject $Data -Depth 100
  [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding $false))
}

# Adds the Windows variant of each shared MCP server to ~/.claude.json.
function Merge-Mcp {
  $path = Join-Path $env:USERPROFILE '.claude.json'
  $data = New-Object PSObject
  if (Test-Path -LiteralPath $path) {
    Copy-Item -LiteralPath $path -Destination "$path.pre-shared-$Stamp"
    $data = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  }
  if (-not $data.PSObject.Properties['mcpServers']) {
    $data | Add-Member -NotePropertyName mcpServers -NotePropertyValue (New-Object PSObject)
  }
  foreach ($server in $Manifest.mcpServers.PSObject.Properties) {
    if ($server.Name.StartsWith('_') -or -not $server.Value.windows) { continue }
    $data.mcpServers | Add-Member -Force -NotePropertyName $server.Name -NotePropertyValue $server.Value.windows
  }
  Write-Json $path $data
  Say "merged shared MCP servers into $path"
}

# settings.json only declares plugins; install whatever is missing here.
function Install-Plugins {
  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Warning 'claude is not on PATH; skipping plugin installs.'
    return
  }
  $plugDir = Join-Path $ClaudeDir 'plugins'
  $known = @()
  $installed = @()
  $knownFile = Join-Path $plugDir 'known_marketplaces.json'
  $installedFile = Join-Path $plugDir 'installed_plugins.json'
  if (Test-Path $knownFile) { $known = @((Get-Content -Raw $knownFile | ConvertFrom-Json).PSObject.Properties.Name) }
  if (Test-Path $installedFile) { $installed = @((Get-Content -Raw $installedFile | ConvertFrom-Json).plugins.PSObject.Properties.Name) }
  $markets = New-Object PSObject
  $plugins = New-Object PSObject
  foreach ($block in @($Manifest.settings, $Manifest.windowsSettings)) {
    if ($block.extraKnownMarketplaces) { Merge-Object $markets $block.extraKnownMarketplaces }
    if ($block.enabledPlugins) { Merge-Object $plugins $block.enabledPlugins }
  }
  foreach ($m in $markets.PSObject.Properties) {
    if ($known -contains $m.Name) { continue }
    $ref = @($m.Value.source.repo, $m.Value.source.path, $m.Value.source.url) | Where-Object { $_ } | Select-Object -First 1
    Say "adding marketplace $($m.Name) ($ref)"
    claude plugin marketplace add $ref
  }
  foreach ($p in $plugins.PSObject.Properties) {
    if ($p.Value -and -not ($installed -contains $p.Name)) {
      Say "installing plugin $($p.Name)"
      claude plugin install --scope user $p.Name
    }
  }
}

# claude-mem's background worker keeps its SQLite database open after
# Claude exits; moving the database while it runs would corrupt it.
function Stop-ClaudeMemWorker {
  $dataDir = Join-Path $env:USERPROFILE '.claude-mem'
  if (Get-Command claude-mem -ErrorAction SilentlyContinue) {
    claude-mem stop 2>&1 | Out-Null
  }
  foreach ($pidFile in @(Get-ChildItem -LiteralPath $dataDir -Filter '*worker.pid' -Force -ErrorAction SilentlyContinue)) {
    $raw = (Get-Content -Raw -LiteralPath $pidFile.FullName).Trim()
    $id = 0
    if ($raw -match '"?pid"?\s*:\s*(\d+)') { $id = [int]$Matches[1] } elseif ($raw -match '^\d+$') { $id = [int]$raw }
    if ($id -and (Get-Process -Id $id -ErrorAction SilentlyContinue)) {
      Stop-Process -Id $id -Force
      Say "stopped claude-mem worker (pid $id)"
    }
    Remove-Item -LiteralPath $pidFile.FullName -Force
  }
  Start-Sleep -Seconds 2
}

function Disable-FastStartup {
  $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
  $on  = (Get-ItemProperty -Path $key -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
  if ($on -ne 1) { Say 'Fast Startup is off (good).'; return }
  $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
  if ($admin) {
    Set-ItemProperty -Path $key -Name HiberbootEnabled -Value 0
    Say 'Fast Startup disabled.'
  } else {
    Write-Warning 'Fast Startup is ON. NixOS will see the shared drive as read-only after a Windows shutdown. Re-run this script as Administrator to turn it off.'
  }
}

if (-not (Test-Path -LiteralPath $SharedRoot)) { throw "shared store $SharedRoot not found" }
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

if ($Uninstall) {
  Stop-ClaudeMemWorker
  foreach ($l in $Links) { Uninstall-Link $l.Local $l.Target }
  Say 'done. The shared store was not touched.'
  return
}

if (Get-Process -Name claude -ErrorAction SilentlyContinue) {
  throw 'Close every Claude Code window first; open sessions would keep writing to the old folders.'
}

Stop-ClaudeMemWorker
foreach ($l in $Links) { Install-Link $l.Local $l.Target $l.LocalWins }
Merge-Settings
Merge-Mcp
Install-Plugins
# Catch up with what NixOS has installed, the same way the hook does.
$hook = Join-Path $ScriptDir 'hook.ps1'
& $hook
& $hook -InstallOnly
Disable-FastStartup

@"
Folders in here (projects, skills, agents, ...) and %USERPROFILE%\.claude-mem
are JUNCTIONS into $SharedRoot, shared with NixOS.

Do NOT delete them with Remove-Item -Recurse or a cleanup tool: that deletes
the shared data. To undo this setup run:
  powershell -ExecutionPolicy Bypass -File "$ScriptDir\bootstrap.ps1" -Uninstall
"@ | Set-Content -LiteralPath (Join-Path $ClaudeDir 'README-SHARED-DO-NOT-DELETE.txt') -Encoding UTF8

Say 'done. Start claude in any project on E:/D: and /resume shows sessions from both OSes.'
