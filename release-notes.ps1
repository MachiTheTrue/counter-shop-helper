<#
.SYNOPSIS
  Writes the CHANGELOG.md section of one version to a Markdown file, ready for `gh release create --notes-file`.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\release-notes.ps1 0.6.3
  # -> prints the path of the notes file (default: %TEMP%\notes-0.6.3.md)

.NOTES
  CHANGELOG.md must have one "## X.Y.Z — YYYY-MM-DD" heading per version. The heading line itself is dropped
  (the release title already names the version); everything below it, up to the next "## " heading, is kept.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Version,
    [string]$Out
)
$ErrorActionPreference = 'Stop'

$changelog = Join-Path $PSScriptRoot 'CHANGELOG.md'
$text = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)

$m = [regex]::Match($text, "(?ms)^## $([regex]::Escape($Version))(?=[ \t\r\n]).*?(?=^## |\z)")
if (-not $m.Success) { throw "CHANGELOG.md has no '## $Version' section. Add it at the top first." }

$parts = $m.Value.Trim() -split "\r?\n", 2
$body = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
if (-not $body) { throw "The '## $Version' section of CHANGELOG.md is empty." }

if (-not $Out) { $Out = Join-Path $env:TEMP "notes-$Version.md" }
[IO.File]::WriteAllText($Out, $body + "`n", (New-Object Text.UTF8Encoding($false)))
$Out
