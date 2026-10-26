#Requires -Version 5.1
<#
.SYNOPSIS
  Claude Code SessionStart hook for the shared NixOS/Windows setup.

.DESCRIPTION
  Generated from the NixOS repo (modules/features/software/claudeSync) and
  registered in settings.json by bootstrap.ps1. Runs however Claude is
  started (claude, headroom wrap claude, VS Code), and on every session:

  - records what is installed here in registry.jsonl, an append-only log
    every OS and user adds to, and records an uninstall when something
    that was here last session is gone (plugins, marketplaces, MCP servers,
    skills). The latest event wins: an uninstall anywhere uninstalls it
    everywhere, a reinstall anywhere brings it back everywhere;
  - adds recorded MCP servers that can run here, drops ones removed elsewhere;
  - installs/uninstalls recorded plugins/marketplaces in the background
    (-InstallOnly);
  - copies claude.ai account skills into the shared skills folder, so they
    survive switching Claude accounts;
  - turns skill links that point at C: (e.g. ~/.agents/skills) into real
    folders on the shared drive, since NixOS can't follow them.

  Does nothing in a sandbox (claude-sandbox.ps1, CLAUDE_CONFIG_DIR set
  elsewhere, or CLAUDE_SHARED_OFF=1).

  More than a few uninstalls at once (a wiped or reset config looks just
  like that) are held, not spread. Run this script by hand with
  -ConfirmRemovals to spread them, or -RestoreRemovals to bring them back.

  Writes one line to stdout, naming the OS for the session (hook stdout
  becomes session context), and nothing else. Logs go to hook-windows.log
  next to this script.
#>
param([switch]$InstallOnly, [switch]$ConfirmRemovals, [switch]$RestoreRemovals)

$ErrorActionPreference = 'Stop'
$SyncDir    = $PSScriptRoot
$SharedRoot = Split-Path -Parent $SyncDir
$ClaudeDir  = Join-Path $env:USERPROFILE '.claude'
$ClaudeJson = Join-Path $env:USERPROFILE '.claude.json'
$PluginsDir = Join-Path $ClaudeDir 'plugins'
$LogFile    = Join-Path $SyncDir 'hook-windows.log'
# Commands that are .cmd scripts on Windows and need a cmd /c shim.
$CmdShimmed = @('npx', 'bunx', 'pnpm', 'yarn', 'npm')
$RegistryLog = Join-Path $SyncDir 'registry.jsonl'
$Who        = "windows:$env:USERNAME"
$StateFile  = [IO.Path]::Combine($SyncDir, 'state', "windows-$env:USERNAME.json")
$SkillsDir  = Join-Path $SharedRoot 'skills'   # ~\.claude\skills is a junction to it
# A failed plugin install is retried at most this often.
$RetrySeconds = 24 * 60 * 60
$AccountMarker = '.account-skill'
# What the registry tracks; skills only record removals and reinstalls.
$Kinds = @('plugin', 'marketplace', 'mcp', 'skill')
# More uninstalls than this at once are held until confirmed.
$MassRemoval = 10
# Removed shared skills stay in _sync\trash this long.
$TrashDays = 30

function Log($msg) { Add-Content -LiteralPath $LogFile -Value "$(Get-Date -Format s) $msg" }

function Read-Json([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try { return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json } catch { return $null }
}

# Write to a temp file, then swap it in: a power cut leaves the old file or
# the new one, never a half-written ~/.claude.json.
function Write-Json([string]$Path, $Data) {
  $json = ConvertTo-Json -InputObject $Data -Depth 100
  $tmp = "$Path.$PID.tmp"
  [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding $false))
  if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp, $Path, [NullString]::Value) }
  else { [IO.File]::Move($tmp, $Path) }
}

function Get-Names($Object) {
  if ($null -eq $Object) { return @() }
  return @($Object.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-Epoch { [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) }

function Read-State {
  $state = Read-Json $StateFile
  if ($null -eq $state) { $state = New-Object PSObject }
  return $state
}

function Write-State($State) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $StateFile) | Out-Null
  Write-Json $StateFile $State
}

# Replays the log in order. Wanted: @{ kind = @{ id = @{ os = spec } } };
# Removed: @{ kind = @{ id = $true } } for items whose latest event is a
# removal. A later add (a reinstall anywhere) takes an item off Removed.
function Read-Registry {
  $wanted = @{}; $removed = @{}
  foreach ($k in $Kinds) { $wanted[$k] = @{}; $removed[$k] = @{} }
  if (-not (Test-Path -LiteralPath $RegistryLog)) { return @{ Wanted = $wanted; Removed = $removed } }
  foreach ($line in [IO.File]::ReadAllLines($RegistryLog)) {
    try { $e = $line | ConvertFrom-Json } catch { continue }   # half-written line
    if (-not $e -or -not $e.kind -or -not $e.id) { continue }
    if (-not $wanted.ContainsKey($e.kind)) { $wanted[$e.kind] = @{}; $removed[$e.kind] = @{} }
    if ($e.removed) {
      $wanted[$e.kind].Remove($e.id)
      $removed[$e.kind][$e.id] = $true
    } elseif ($e.os) {
      if (-not $wanted[$e.kind].ContainsKey($e.id)) { $wanted[$e.kind][$e.id] = @{} }
      $wanted[$e.kind][$e.id][$e.os] = $e.spec
      $removed[$e.kind].Remove($e.id)
    }
  }
  return @{ Wanted = $wanted; Removed = $removed }
}

function Get-SpecJson($Spec) {
  if ($null -eq $Spec) { return '{}' }
  return (ConvertTo-Json -InputObject $Spec -Depth 50 -Compress)
}

function Add-Events([string[]]$Lines) {
  if (-not $Lines) { return }
  # A power cut mid-append can leave a last line without its newline; start
  # on a fresh line so only that one event is lost (re-recorded next run).
  $sep = ''
  if ((Test-Path -LiteralPath $RegistryLog) -and (Get-Item -LiteralPath $RegistryLog).Length -gt 0) {
    $fs = [IO.File]::OpenRead($RegistryLog)
    try { [void]$fs.Seek(-1, [IO.SeekOrigin]::End); if ($fs.ReadByte() -ne 10) { $sep = "`n" } } finally { $fs.Dispose() }
  }
  [IO.File]::AppendAllText($RegistryLog, ($sep + ($Lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
}

# Folders in the shared skills dir. One skill-update is swapping (its folder
# is briefly gone) still counts as here.
function Get-SkillsHere {
  if (-not (Test-Path -LiteralPath $SkillsDir)) { return $null }
  $exclude = @((Read-Json (Join-Path $SyncDir 'shared.json')).perEntryExclude)
  $names = @{}
  foreach ($d in @(Get-ChildItem -LiteralPath $SkillsDir -Directory -Force -ErrorAction Stop)) {
    if ($d.Name.StartsWith('.') -or $exclude -contains $d.Name -or $d.Name -like '*.materializing') { continue }
    $names[$d.Name] = New-Object PSObject
  }
  foreach ($j in @(Get-ChildItem -LiteralPath (Join-Path $SyncDir 'tmp') -Filter 'swap-*.json' -ErrorAction SilentlyContinue)) {
    $names[($j.Name -replace '^swap-', '' -replace '\.json$', '')] = New-Object PSObject
  }
  return $names
}

# @{ kind = @{ id = spec } }; a kind is $null when its config can't be read,
# so a broken file never reads as "everything was uninstalled".
function Get-InstalledHere {
  $known = Read-Json (Join-Path $PluginsDir 'known_marketplaces.json')
  $markets = $null
  if ($null -ne $known) { $markets = @{}; foreach ($name in Get-Names $known) { $markets[$name] = $known.$name.source } }
  $installed = Read-Json (Join-Path $PluginsDir 'installed_plugins.json')
  $plugins = $null
  if ($installed -and $installed.PSObject.Properties['plugins']) {
    $plugins = @{}; foreach ($p in Get-Names $installed.plugins) { $plugins[$p] = New-Object PSObject }
  }
  $config = Read-Json $ClaudeJson
  $mcp = $null
  if ($config -and $config.PSObject.Properties['mcpServers']) {
    $mcp = @{}; foreach ($n in Get-Names $config.mcpServers) { $mcp[$n] = $config.mcpServers.$n }
  }
  return @{ plugin = $plugins; marketplace = $markets; mcp = $mcp; skill = (Get-SkillsHere) }
}

function Get-StateList($Object, [string]$Kind) {
  if ($Object -and $Object.PSObject.Properties[$Kind]) { return @($Object.$Kind | Where-Object { $_ }) }
  return @()
}

# Spreads uninstalls, then records what is installed here. Gone since last
# session = uninstalled here: recorded as removed for every OS and user.
# Removed elsewhere and still here = uninstalled here too (MCP servers and
# skills now, plugins by -InstallOnly in the background). Mode 'confirm'
# lets a held mass removal through; 'restore' drops it instead.
function Sync-Removals([string]$Mode) {
  $reg = Read-Registry
  $wanted = $reg.Wanted; $removed = $reg.Removed
  $current = Get-InstalledHere
  $state = Read-State
  $seen = $state.seen; $heldBefore = $state.held
  $stamp = Get-Date -Format s
  $events = @(); $newSeen = [ordered]@{}; $held = [ordered]@{}
  $dropMcp = @(); $dropSkills = @()
  foreach ($kind in $Kinds) {
    $here = $current[$kind]
    $hadSeen = [bool]($seen -and $seen.PSObject.Properties[$kind])
    $heldKind = @(Get-StateList $heldBefore $kind)
    if ($null -eq $here) {   # unreadable right now: change nothing
      if ($hadSeen) { $newSeen[$kind] = @(Get-StateList $seen $kind) }
      if ($heldKind) { $held[$kind] = $heldKind }
      continue
    }
    $rem = $removed[$kind]
    # First run here (or for this kind): nothing counts as uninstalled.
    $before = @(if ($hadSeen) { Get-StateList $seen $kind } else { $here.Keys })
    if ($Mode -eq 'restore') { $before = @($before | Where-Object { $heldKind -notcontains $_ }) }
    $gone = @($before | Where-Object { -not $here.ContainsKey($_) -and -not $rem.ContainsKey($_) } | Sort-Object)
    if ($gone.Count -and $Mode -ne 'confirm' -and ($gone.Count -gt $MassRemoval -or ($before.Count -ge 4 -and $here.Count -eq 0))) {
      $held[$kind] = $gone
      if (($gone -join ',') -ne (@($heldKind | Sort-Object) -join ',')) {
        Log "$($gone.Count) $kind(s) disappeared at once; NOT spreading that to other OSes/users. If you meant it, run hook.ps1 -ConfirmRemovals (undo: -RestoreRemovals)"
      }
    } else {
      foreach ($id in $gone) {
        $events += ConvertTo-Json -Compress -InputObject ([PSCustomObject]@{ at = $stamp; by = $Who; kind = $kind; id = $id; removed = $true })
        $wanted[$kind].Remove($id)
        $rem[$id] = $true
        Log "$kind $id uninstalled here; removing it on every OS and user"
      }
    }
    $stale = @($before | Where-Object { $here.ContainsKey($_) -and $rem.ContainsKey($_) })
    if ($kind -eq 'mcp') { $dropMcp = $stale }
    if ($kind -eq 'skill') {
      # Also finishes a removal a crash interrupted.
      $dropSkills = @($stale) + @($before | Where-Object { -not $here.ContainsKey($_) -and $rem.ContainsKey($_) })
    }
    $keep = @($here.Keys | Where-Object { -not (($kind -eq 'mcp' -or $kind -eq 'skill') -and $stale -contains $_) })
    $newSeen[$kind] = @(@($keep) + @($held[$kind]) | Where-Object { $_ } | Sort-Object -Unique)
    foreach ($id in @($here.Keys)) {
      if ($stale -contains $id) { continue }
      # Skills: only a reinstall of a removed one needs an event.
      if ($kind -eq 'skill' -and -not ($before -notcontains $id -and $rem.ContainsKey($id))) { continue }
      $spec = $here[$id]
      $known = $wanted[$kind][$id]
      if ($known -and $known.ContainsKey('windows') -and (Get-SpecJson $known['windows']) -eq (Get-SpecJson $spec)) { continue }
      $events += ConvertTo-Json -Compress -Depth 50 -InputObject ([PSCustomObject]@{
        at = $stamp; by = $Who; os = 'windows'; kind = $kind; id = $id; spec = $spec })
    }
  }
  # Log first: if the power goes now, the next run finishes the job.
  Add-Events $events
  if ($dropMcp) {
    $data = Read-Json $ClaudeJson
    if ($data -and $data.mcpServers) {
      foreach ($name in $dropMcp) { $data.mcpServers.PSObject.Properties.Remove($name) }
      Write-Json $ClaudeJson $data
      Log "removed MCP servers uninstalled elsewhere: $($dropMcp -join ', ')"
    }
  }
  foreach ($name in @($dropSkills | Sort-Object -Unique)) { Remove-SharedSkill $name }
  $state = Read-State
  $state | Add-Member -Force -NotePropertyName seen -NotePropertyValue ([PSCustomObject]$newSeen)
  $state | Add-Member -Force -NotePropertyName held -NotePropertyValue ([PSCustomObject]$held)
  Write-State $state
}

# Moves a shared skill to _sync\trash (same drive: a rename, so a power cut
# leaves it in one place or the other). Purged after $TrashDays days.
function Remove-SharedSkill([string]$Name) {
  $live = Join-Path $SkillsDir $Name
  if (-not (Test-Path -LiteralPath $live)) { return }
  $trash = [IO.Path]::Combine($SyncDir, 'trash', 'skills', "$Name@$(Get-Date -Format 'yyyyMMdd-HHmmss')")
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $trash) | Out-Null
  Move-Item -LiteralPath $live -Destination $trash
  Log "skill $Name removed everywhere; kept in $trash for $TrashDays days"
}

function Clear-Trash {
  $dir = [IO.Path]::Combine($SyncDir, 'trash', 'skills')
  if (-not (Test-Path -LiteralPath $dir)) { return }
  $cutoff = (Get-Date).AddDays(-$TrashDays)
  foreach ($d in @(Get-ChildItem -LiteralPath $dir -Directory -Force)) {
    $at = [datetime]::MinValue
    if (-not [datetime]::TryParseExact(($d.Name -split '@')[-1], 'yyyyMMdd-HHmmss', $null, 'None', [ref]$at) -or $at -ge $cutoff) { continue }
    # rmdir /s removes junctions inside without following them; Remove-Item
    # -Recurse in PowerShell 5.1 would delete what they point at.
    if ($IsLinux -or $IsMacOS) { Remove-Item -LiteralPath $d.FullName -Recurse -Force }
    else { cmd /c rmdir /s /q "$($d.FullName)" | Out-Null }
  }
}

# A NixOS MCP entry rewritten for Windows, or $null if it can't run here.
function ConvertTo-WindowsServer($Spec) {
  if ($Spec.url) { return $Spec }
  $command = [string]$Spec.command
  if (-not $command -or $command -match '[\\/]') { return $null }
  foreach ($arg in @($Spec.args)) { if ([string]$arg -match '^/(mnt|home|nix|run|etc)/') { return $null } }
  if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { return $null }
  $copy = $Spec | ConvertTo-Json -Depth 50 | ConvertFrom-Json
  if ($CmdShimmed -contains $command) {
    $copy.command = 'cmd'
    $copy.args = @('/c', $command) + @($Spec.args)
  }
  return $copy
}

function Import-Mcp {
  $wanted = (Read-Registry).Wanted.mcp
  if (-not $wanted.Count) { return }
  $data = Read-Json $ClaudeJson
  if ($null -eq $data) { return }
  if (-not $data.PSObject.Properties['mcpServers']) {
    $data | Add-Member -NotePropertyName mcpServers -NotePropertyValue (New-Object PSObject)
  }
  $have = Get-Names $data.mcpServers
  $state = Read-State
  $reported = @($state.mcpUnsupported)
  $added = @(); $unsupported = @()
  foreach ($name in $wanted.Keys) {
    if ($have -contains $name) { continue }
    $specs = $wanted[$name]
    $converted = $specs['windows']
    if ($null -eq $converted) {
      foreach ($spec in $specs.Values) {
        $converted = ConvertTo-WindowsServer $spec
        if ($null -ne $converted) { break }
      }
    }
    if ($null -eq $converted) { $unsupported += $name; continue }
    $data.mcpServers | Add-Member -NotePropertyName $name -NotePropertyValue $converted
    $added += $name
  }
  if ($added) {
    Write-Json $ClaudeJson $data
    Log "added MCP servers from the registry: $($added -join ', ')"
  }
  foreach ($name in $unsupported | Sort-Object) {
    if ($reported -notcontains $name) { Log "MCP server $name can't run here; add a 'windows' entry for it in shared.json" }
  }
  if ((@($unsupported | Sort-Object) -join ',') -ne (@($reported | Sort-Object) -join ',')) {
    $state | Add-Member -Force -NotePropertyName mcpUnsupported -NotePropertyValue @($unsupported | Sort-Object)
    Write-State $state
  }
}

# Recorded plugins and marketplaces missing here, minus recent failures.
function Get-Missing {
  $wanted = (Read-Registry).Wanted
  $known = Get-Names (Read-Json (Join-Path $PluginsDir 'known_marketplaces.json'))
  $installed = Get-Names (Read-Json (Join-Path $PluginsDir 'installed_plugins.json')).plugins
  $failed = (Read-State).failed
  $now = Get-Epoch
  $recent = @(Get-Names $failed | Where-Object { $now - [int64]$failed.$_ -lt $RetrySeconds })
  $markets = @()
  foreach ($name in $wanted.marketplace.Keys) {
    if ($known -contains $name -or $recent -contains $name) { continue }
    $specs = $wanted.marketplace[$name]
    $src = if ($specs.ContainsKey('windows')) { $specs['windows'] } else { @($specs.Values)[0] }
    $markets += [PSCustomObject]@{ Name = $name; Source = $src }
  }
  $marketNames = $known + @($markets | ForEach-Object { $_.Name })
  $plugins = @($wanted.plugin.Keys | Where-Object {
    $installed -notcontains $_ -and $recent -notcontains $_ -and $marketNames -contains ($_ -split '@')[-1] })
  return [PSCustomObject]@{ Markets = $markets; Plugins = $plugins }
}

# Plugins and marketplaces installed here that were uninstalled elsewhere.
# Only ones this user already had: one installed since is a reinstall,
# which the next session records instead.
function Get-Unwanted {
  $removed = (Read-Registry).Removed
  $state = Read-State
  if (-not $state.seen) { return [PSCustomObject]@{ Markets = @(); Plugins = @() } }
  $now = Get-Epoch
  $recent = @(Get-Names $state.failed | Where-Object { $now - [int64]$state.failed.$_ -lt $RetrySeconds })
  $installed = Get-Names (Read-Json (Join-Path $PluginsDir 'installed_plugins.json')).plugins
  $known = Get-Names (Read-Json (Join-Path $PluginsDir 'known_marketplaces.json'))
  $seenPlugins = @(Get-StateList $state.seen 'plugin'); $seenMarkets = @(Get-StateList $state.seen 'marketplace')
  return [PSCustomObject]@{
    Plugins = @($installed | Where-Object { $removed.plugin.ContainsKey($_) -and $seenPlugins -contains $_ -and $recent -notcontains "uninstall:$_" })
    Markets = @($known | Where-Object { $removed.marketplace.ContainsKey($_) -and $seenMarkets -contains $_ -and $recent -notcontains "uninstall:$_" })
  }
}

function Install-Missing {
  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Log 'claude is not on PATH; cannot install plugins'; return }
  $failed = @()
  $unwanted = Get-Unwanted
  foreach ($p in $unwanted.Plugins) {
    Log "uninstalling plugin $p (uninstalled on another OS or user)"
    $out = & claude plugin uninstall --scope user $p 2>&1
    $code = $LASTEXITCODE
    Add-Content -LiteralPath $LogFile -Value ($out | Out-String).Trim()
    if ($code) { $failed += "uninstall:$p" }
  }
  foreach ($m in $unwanted.Markets) {
    Log "removing marketplace $m (removed on another OS or user)"
    $out = & claude plugin marketplace remove $m 2>&1
    $code = $LASTEXITCODE
    Add-Content -LiteralPath $LogFile -Value ($out | Out-String).Trim()
    if ($code) { $failed += "uninstall:$m" }
  }
  $missing = Get-Missing
  foreach ($m in $missing.Markets) {
    $src = $m.Source
    $ref = @($src.repo, $src.path, $src.url) | Where-Object { $_ } | Select-Object -First 1
    if (-not $ref) { continue }
    Log "adding marketplace $($m.Name) ($ref)"
    $out = & claude plugin marketplace add $ref 2>&1
    $code = $LASTEXITCODE
    Add-Content -LiteralPath $LogFile -Value ($out | Out-String).Trim()
    if ($code) { $failed += $m.Name }
  }
  foreach ($p in $missing.Plugins) {
    Log "installing plugin $p"
    $out = & claude plugin install --scope user $p 2>&1
    $code = $LASTEXITCODE
    Add-Content -LiteralPath $LogFile -Value ($out | Out-String).Trim()
    if ($code) { $failed += $p }
  }
  $state = Read-State
  $now = Get-Epoch
  $keep = New-Object PSObject
  foreach ($k in Get-Names $state.failed) {
    if ($now - [int64]$state.failed.$k -lt $RetrySeconds) { $keep | Add-Member -NotePropertyName $k -NotePropertyValue $state.failed.$k }
  }
  foreach ($item in $failed) {
    Log "$item failed; retrying in $($RetrySeconds / 3600)h"
    $keep | Add-Member -Force -NotePropertyName $item -NotePropertyValue $now
  }
  $state | Add-Member -Force -NotePropertyName failed -NotePropertyValue $keep
  Write-State $state
}

# Skills a claude.ai login syncs in live per account (skills\synced\<org>_<account>,
# plugins\synced\...), so they vanish on switching accounts. Copy them into
# the shared skills folder; adds and updates only, never deletes. Skipped:
# Anthropic's built-ins (every account has them) and anything a locally
# installed plugin already provides.
function Sync-AccountSkills {
  $skillsDir = Join-Path $ClaudeDir 'skills'
  $havePlugins = @(); $haveSkills = @()
  $installed = (Read-Json (Join-Path $PluginsDir 'installed_plugins.json')).plugins
  foreach ($key in Get-Names $installed) {
    $havePlugins += ($key -split '@')[0]
    foreach ($entry in @($installed.$key)) {
      $dir = Join-Path ([string]$entry.installPath) 'skills'
      if ($entry.installPath -and (Test-Path -LiteralPath $dir)) { $haveSkills += @(Get-ChildItem -LiteralPath $dir -Directory | ForEach-Object { $_.Name }) }
    }
  }
  $found = [ordered]@{}
  foreach ($manifest in @(Get-ChildItem -Path (Join-Path $skillsDir 'synced\*\manifest.json') -ErrorAction SilentlyContinue | Sort-Object FullName)) {
    foreach ($skill in @((Read-Json $manifest.FullName).skills)) {
      $name = [string]$skill.name
      $src = Join-Path $manifest.DirectoryName $name
      if ($skill.source -eq 'plugin' -and $name -and $haveSkills -notcontains $name -and
          (Test-Path -LiteralPath (Join-Path $src 'SKILL.md')) -and -not $found.Contains($name)) { $found[$name] = $src }
    }
  }
  foreach ($meta in @(Get-ChildItem -Path (Join-Path $PluginsDir 'synced\*\*.meta.json') -ErrorAction SilentlyContinue | Sort-Object FullName)) {
    $plugin = Join-Path $meta.DirectoryName ($meta.Name -replace '\.meta\.json$', '')
    $pname = (Read-Json (Join-Path $plugin '.claude-plugin\plugin.json')).name
    if (-not $pname) { $pname = Split-Path -Leaf $plugin }
    if ($havePlugins -contains $pname) { continue }
    foreach ($md in @(Get-ChildItem -Path (Join-Path $plugin 'skills\*\SKILL.md') -ErrorAction SilentlyContinue | Sort-Object FullName)) {
      # Prefixed: plugin skills have generic names (start, update).
      $name = "$pname-$($md.Directory.Name)"
      if (-not $found.Contains($name)) { $found[$name] = $md.DirectoryName }
    }
  }
  $removed = (Read-Registry).Removed.skill
  $sha = [Security.Cryptography.SHA256]::Create()
  foreach ($name in $found.Keys) {
    if ($name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { continue }  # stay inside skills\
    if ($removed.ContainsKey($name)) { continue }  # uninstalled somewhere; the account copy doesn't bring it back
    $src = $found[$name]
    $dest = Join-Path $skillsDir $name
    $marker = Join-Path $dest $AccountMarker
    if ((Test-Path -LiteralPath $dest) -and -not (Test-Path -LiteralPath $marker)) { continue }  # unrelated skill
    # Content hash, same as claude-shared.py: mtimes differ between OSes.
    $files = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $src -Recurse -File)) { $files[$f.FullName.Substring($src.Length + 1).Replace('\', '/')] = $f.FullName }
    [string[]]$rels = @($files.Keys)
    [Array]::Sort($rels, [StringComparer]::Ordinal)   # same order as claude-shared.py
    $buf = New-Object IO.MemoryStream
    foreach ($rel in $rels) {
      $relBytes = [Text.Encoding]::UTF8.GetBytes($rel)
      $buf.Write($relBytes, 0, $relBytes.Length); $buf.WriteByte(0)
      $bytes = [IO.File]::ReadAllBytes($files[$rel]); $buf.Write($bytes, 0, $bytes.Length)
    }
    $stamp = -join ($sha.ComputeHash($buf.ToArray()) | ForEach-Object { $_.ToString('x2') })
    if ((Test-Path -LiteralPath $marker) -and (Get-Content -Raw -LiteralPath $marker) -eq $stamp) { continue }
    # Marker first (with no hash): an interrupted copy is redone next run.
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    [IO.File]::WriteAllText($marker, 'copying', (New-Object Text.UTF8Encoding $false))
    robocopy $src $dest /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Log "could not copy account skill $name"; continue }
    [IO.File]::WriteAllText($marker, $stamp, (New-Object Text.UTF8Encoding $false))
    Log "shared account skill $name"
  }
}

# Skills installed as links to C: become real folders NixOS can read.
# '.linked-from' remembers the source so later updates there still flow in.
function Repair-SkillLinks {
  $skills = Join-Path $ClaudeDir 'skills'
  # Finish a swap a crash interrupted: the copy is complete once it has its
  # marker; if the link is already gone, move the copy into place.
  foreach ($tmp in @(Get-ChildItem -LiteralPath $skills -Directory -Force -Filter '*.materializing' -ErrorAction SilentlyContinue)) {
    $name = $tmp.Name -replace '\.materializing$', ''
    $live = Join-Path $skills $name
    if (-not (Test-Path -LiteralPath $live) -and (Test-Path -LiteralPath (Join-Path $tmp.FullName '.linked-from'))) {
      Rename-Item -LiteralPath $tmp.FullName -NewName $name
      Log "recovered skill $name after an interrupted copy"
    } elseif (Test-Path -LiteralPath $live) {
      Remove-Item -LiteralPath $tmp.FullName -Recurse -Force   # our own stale copy; the original is untouched
    }
  }
  foreach ($item in @(Get-ChildItem -LiteralPath $skills -Force -ErrorAction SilentlyContinue)) {
    $marker = Join-Path $item.FullName '.linked-from'
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
      $source = @($item.Target)[0]
      if (-not $source -or -not (Test-Path -LiteralPath $source)) { continue }
      $tmp = "$($item.FullName).materializing"
      robocopy $source $tmp /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
      if ($LASTEXITCODE -ge 8) { Log "could not copy skill $($item.Name) from $source"; continue }
      # Marker inside the copy before the swap: it also tells a later run the copy is complete.
      Set-Content -LiteralPath (Join-Path $tmp '.linked-from') -Value $source
      cmd /c rmdir "$($item.FullName)" | Out-Null   # removes the link only
      Rename-Item -LiteralPath $tmp -NewName $item.Name
      Log "skill $($item.Name) copied from $source so NixOS can use it"
    } elseif (Test-Path -LiteralPath $marker) {
      $source = (Get-Content -Raw -LiteralPath $marker).Trim()
      if (Test-Path -LiteralPath $source) {
        robocopy $source $item.FullName /MIR /XF .linked-from /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
      }
    }
  }
}

# The only stdout: tells this session which OS it runs on, so it doesn't try
# NixOS commands here. Skipped for the background -InstallOnly run.
if (-not ($InstallOnly -or $ConfirmRemovals -or $RestoreRemovals)) {
  [Console]::Out.WriteLine("Session OS: Windows, user $env:USERNAME. Dual-boot with NixOS; the shared drive is E:\ here (/mnt/E_Drive on NixOS). Use Windows commands and paths (PowerShell, or Git Bash for the Bash tool); never NixOS/Linux-only commands (nix, nixos-rebuild, systemctl, /etc, /mnt/E_Drive paths). Don't re-check the OS.")
}

try {
  if (-not (Test-Path -LiteralPath $SyncDir)) { exit 0 }
  # Sandbox: nothing done there is recorded or shared.
  if ($env:CLAUDE_SHARED_OFF -eq '1') { exit 0 }
  if ($env:CLAUDE_CONFIG_DIR -and
      [IO.Path]::GetFullPath($env:CLAUDE_CONFIG_DIR).TrimEnd('\', '/') -ne [IO.Path]::GetFullPath($ClaudeDir).TrimEnd('\', '/')) { exit 0 }
  if ($ConfirmRemovals -or $RestoreRemovals) {
    Sync-Removals $(if ($ConfirmRemovals) { 'confirm' } else { 'restore' })
    $held = (Read-State).held
    if (-not (Get-Names $held)) { Write-Host 'no uninstalls are held' }
    foreach ($k in Get-Names $held) { Write-Host "held $($k): $(@($held.$k) -join ', ')" }
    exit 0
  }
  if ($InstallOnly) {
    Install-Missing
    exit 0
  }
  Repair-SkillLinks
  Sync-Removals ''
  Sync-AccountSkills
  Import-Mcp
  Clear-Trash
  $missing = Get-Missing
  $unwanted = Get-Unwanted
  if ($env:CLAUDE_SHARED_FOREGROUND -eq '1') {   # tests
    if ($missing.Markets -or $missing.Plugins -or $unwanted.Plugins -or $unwanted.Markets) { Install-Missing }
    exit 0
  }
  if ($missing.Markets -or $missing.Plugins -or $unwanted.Plugins -or $unwanted.Markets) {
    # Installs take minutes; finish in the background, live next session.
    Start-Process powershell -WindowStyle Hidden -ArgumentList @(
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-InstallOnly')
  }
  # Refresh shared skills from upstream (same script NixOS runs). It checks
  # each repo at most daily and returns at once otherwise. Runs with bun, or
  # with node (every Windows user has it via Program Files) when bun is missing.
  $updater = Join-Path $SyncDir 'skill-update.ts'
  if (Test-Path -LiteralPath $updater) {
    $runtime = $null; $pre = @()
    $bun = Get-Command bun -ErrorAction SilentlyContinue
    $userBun = Join-Path $env:USERPROFILE '.bun\bin\bun.exe'
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($bun) { $runtime = $bun.Source }
    elseif (Test-Path -LiteralPath $userBun) { $runtime = $userBun }
    elseif ($node) { $runtime = $node.Source; $pre = @('--experimental-strip-types', '--no-warnings') }
    if ($runtime) {
      $out = Join-Path $SyncDir "state\skill-update-$env:USERNAME"
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out) | Out-Null
      Start-Process $runtime -WindowStyle Hidden -RedirectStandardOutput "$out.out" -RedirectStandardError "$out.err" -ArgumentList (
        $pre + @("`"$updater`"", '--shared', "`"$SharedRoot`"", '--manifest', "`"$(Join-Path $SyncDir 'shared.json')`"",
        '--lock', "`"$(Join-Path $env:USERPROFILE '.agents\.skill-lock.json')`""))
    } elseif (-not (Read-State).noRuntimeLogged) {
      Log 'skill updates need bun or node; neither is installed for this user (another user or NixOS still updates the shared skills)'
      $state = Read-State; $state | Add-Member -Force -NotePropertyName noRuntimeLogged -NotePropertyValue $true; Write-State $state
    }
  }
} catch {
  Log "hook failed: $_"
}
exit 0
