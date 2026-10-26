#Requires -Version 5.1
<#
.SYNOPSIS
  Claude Code in a sandbox: its own config dir (~\.claude-sandbox), seeded
  from ~\.claude.

.DESCRIPTION
  Plugins, skills, MCP servers, sessions and claude-mem memories installed,
  removed or created there stay there: nothing reaches ~\.claude, the shared
  drive, NixOS or the other Windows user. The sandbox keeps its own login
  (run /login once). -Reset re-seeds it from ~\.claude.

  Run from anywhere:  & E:\.claude-shared\_sync\claude-sandbox.ps1 [-Reset] [claude args]
#>
param([switch]$Reset, [Parameter(ValueFromRemainingArguments = $true)] $ClaudeArgs)

$ErrorActionPreference = 'Stop'
$Box  = if ($env:CLAUDE_SANDBOX_DIR) { $env:CLAUDE_SANDBOX_DIR } else { Join-Path $env:USERPROFILE '.claude-sandbox' }
$Real = Join-Path $env:USERPROFILE '.claude'

if ($Reset -and (Test-Path -LiteralPath $Box)) {
  # Keep only the sandbox's login. rmdir /s never follows junctions.
  foreach ($item in @(Get-ChildItem -LiteralPath $Box -Force | Where-Object { $_.Name -ne '.credentials.json' })) {
    if ($item.PSIsContainer) { cmd /c rmdir /s /q "$($item.FullName)" | Out-Null } else { Remove-Item -LiteralPath $item.FullName -Force }
  }
}

if (-not (Test-Path -LiteralPath (Join-Path $Box '.seeded'))) {
  Write-Host "claude-sandbox: copying $Real into $Box (once; -Reset to redo)"
  New-Item -ItemType Directory -Force -Path (Join-Path $Box 'skills') | Out-Null
  # Real copies, not links: deleting something here must never reach the
  # originals. Plugins hold absolute paths, rewritten below.
  $plugins = Join-Path $Real 'plugins'
  if (Test-Path -LiteralPath $plugins) {
    robocopy $plugins (Join-Path $Box 'plugins') /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    $from = (ConvertTo-Json $plugins).Trim('"'); $to = (ConvertTo-Json (Join-Path $Box 'plugins')).Trim('"')
    foreach ($f in 'installed_plugins.json', 'known_marketplaces.json') {
      $path = Join-Path $Box "plugins\$f"
      if (Test-Path -LiteralPath $path) {
        $text = [IO.File]::ReadAllText($path).Replace($from, $to)
        [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false))
      }
    }
  }
  # Skills: ~\.claude\skills is a junction to the shared drive; copy its contents.
  $skills = Join-Path $Real 'skills'
  if (Test-Path -LiteralPath $skills) {
    robocopy $skills (Join-Path $Box 'skills') /E /R:1 /W:1 /XD synced /NFL /NDL /NJH /NJS /NP | Out-Null
  }
  # Settings without the sharing hook; MCP servers from ~\.claude.json.
  $settings = Join-Path $Real 'settings.json'
  if (Test-Path -LiteralPath $settings) {
    $data = Get-Content -Raw -LiteralPath $settings | ConvertFrom-Json
    if ($data.hooks -and $data.hooks.SessionStart) {
      $data.hooks.SessionStart = @($data.hooks.SessionStart | Where-Object {
        -not (@($_.hooks) | Where-Object { [string]$_.command -match 'hook\.ps1|claude-shared' }) })
    }
    [IO.File]::WriteAllText((Join-Path $Box 'settings.json'), (ConvertTo-Json $data -Depth 100), (New-Object Text.UTF8Encoding $false))
  }
  $config = Join-Path $env:USERPROFILE '.claude.json'
  $servers = New-Object PSObject
  if (Test-Path -LiteralPath $config) {
    $parsed = (Get-Content -Raw -LiteralPath $config | ConvertFrom-Json).mcpServers
    if ($parsed) { $servers = $parsed }
  }
  [IO.File]::WriteAllText((Join-Path $Box '.claude.json'),
    (ConvertTo-Json -Depth 100 ([PSCustomObject]@{ mcpServers = $servers; hasCompletedOnboarding = $true })), (New-Object Text.UTF8Encoding $false))
  New-Item -ItemType File -Force -Path (Join-Path $Box '.seeded') | Out-Null
}

$env:CLAUDE_CONFIG_DIR = $Box
$env:CLAUDE_SHARED_OFF = '1'
# claude-mem: own database and worker, so sandbox sessions never reach the shared memory.
$env:CLAUDE_MEM_DATA_DIR = Join-Path $Box 'claude-mem'
$env:CLAUDE_MEM_WORKER_PORT = '37787'
& claude @ClaudeArgs
exit $LASTEXITCODE
