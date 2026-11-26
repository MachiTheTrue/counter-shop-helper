<#
.SYNOPSIS
  Checks one release version against the versioning rules of RELEASE.md: the same MAJOR.MINOR.PATCH in every
  file that carries it, exactly one step after the latest vX.Y.Z tag (no skipped or reused number).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\check-version.ps1 0.7.1
  # before tagging: every file says 0.7.1, no v0.7.1 tag yet, 0.7.1 follows the latest tag

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\check-version.ps1 0.7.1 -Released
  # after the GitHub release, before `mod publish`: also the annotated tag, the manifest at that tag,
  # the package in dist\ and the GitHub release (title, asset name, same SHA-256 as the local package)

.NOTES
  Reads only: changes no file, tag or release. Prints what it found and ends with "OK", or lists every
  mismatch and exits with code 1.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Version,
    [switch]$Released
)
Set-Location $PSScriptRoot
if ($Version -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
    Write-Host "'$Version' is not MAJOR.MINOR.PATCH (for example 0.7.1)."
    exit 1
}
$problems = New-Object System.Collections.Generic.List[string]
$V = '(\d+\.\d+\.\d+)'

# Every place that carries the version: file, pattern (group 1 is the version), label, first match only.
$places = @(
    @('src/manifest.toml', "^version = `"$V`"", 'version', $false),
    @('src/scripts/main.lua', "^local VERSION = `"$V`"", 'VERSION', $false),
    @('CHANGELOG.md', "^## $V ", 'top section', $true),
    @('README.md', "^- \*\*Current version:\*\* $V", 'current version', $false),
    @('RELEASE.md', "^\| Current version \| $V \|", 'current version', $false),
    @('DEVELOPPEMENT.md', "^\| Version \| $V ", 'version row', $false),
    @('DEVELOPPEMENT.md', "-$V\.tempest`"", 'pack command', $false),
    @('engine/tests/lua_tests.lua', "report v$V`"", 'expected report line', $false)
)
foreach ($p in $places) {
    $file, $pattern, $what, $firstOnly = $p
    $text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot $file), [Text.Encoding]::UTF8)
    $found = @([regex]::Matches($text, $pattern, 'Multiline') | ForEach-Object { $_.Groups[1].Value })
    if ($firstOnly) { $found = @($found | Select-Object -First 1) }
    $shown = if ($found.Count) { (@($found | Sort-Object -Unique)) -join ', ' } else { '(not found)' }
    '{0,-28} {1,-22} {2}' -f $file, $what, $shown
    if (-not $found.Count -or @($found | Where-Object { $_ -ne $Version }).Count) {
        $problems.Add("$file ($what) says $shown, not $Version")
    }
}

# Native commands print their errors on stderr; keep them quiet and read the exit code instead.
function Invoke-Quiet([scriptblock]$Command) {
    $ErrorActionPreference = 'Continue'
    & $Command 2>$null
}

# One step after the release before it: PATCH + 1, MINOR + 1 (PATCH 0) or MAJOR + 1 (MINOR and PATCH 0).
$want = [version]$Version
$tags = @(Invoke-Quiet { git tag -l 'v*' } | Where-Object { $_ -match '^v\d+\.\d+\.\d+$' } |
        ForEach-Object { [version]$_.Substring(1) } | Sort-Object)
$before = @($tags | Where-Object { $_ -lt $want }) | Select-Object -Last 1
if ($before) {
    $next = @("$($before.Major).$($before.Minor).$($before.Build + 1)",
              "$($before.Major).$($before.Minor + 1).0",
              "$($before.Major + 1).0.0")
    'previous release             v{0}; the next version is {1}' -f $before, ($next -join ', ')
    if ($next -notcontains $Version) { $problems.Add("$Version is not one step after v$($before): use $($next -join ', ')") }
}
$newer = @($tags | Where-Object { $_ -gt $want })
if ($newer.Count) { $problems.Add("newer tags exist: v$(($newer | ForEach-Object { "$_" }) -join ', v')") }

$tag = "v$Version"
$package = "dist\Paladins-SmartCounter-8.1-$Version.tempest"
if (-not $Released) {
    if ($tags -contains $want) {
        $problems.Add("$tag is already released: a released number is never rebuilt, the next change takes the next version")
    }
} else {
    if ((Invoke-Quiet { git cat-file -t $tag }) -ne 'tag') {
        $problems.Add("$tag is missing or not an annotated tag (git tag -a)")
    } else {
        $atTag = (Invoke-Quiet { git show "$($tag):src/manifest.toml" }) -join "`n"
        $m = [regex]::Match($atTag, "(?m)^version = `"$V`"")
        $shown = if ($m.Success) { $m.Groups[1].Value } else { '(not found)' }
        '{0,-28} {1,-22} {2}' -f "$tag (annotated tag)", 'manifest at the tag', $shown
        if ($shown -ne $Version) { $problems.Add("src/manifest.toml at $tag says $shown") }
    }
    if (-not (Test-Path $package)) {
        $problems.Add("$package is missing")
    } else {
        $hash = (Get-FileHash $package -Algorithm SHA256).Hash.ToLower()
        $json = (Invoke-Quiet { gh release view $tag --json name,tagName,assets }) -join "`n"
        if ($LASTEXITCODE -ne 0 -or -not $json) {
            $problems.Add("GitHub release $tag not found (gh release create)")
        } else {
            $release = $json | ConvertFrom-Json
            $asset = @($release.assets | Where-Object { $_.name -eq (Split-Path $package -Leaf) }) | Select-Object -First 1
            '{0,-28} {1,-22} {2}' -f "GitHub release $tag", 'title', $release.name
            if ($release.name -ne "Counter & Shop Helper $Version") { $problems.Add("GitHub release title is '$($release.name)'") }
            if (-not $asset) {
                $problems.Add("GitHub release $tag has no asset $(Split-Path $package -Leaf)")
            } elseif ($asset.digest -and $asset.digest -ne "sha256:$hash") {
                $problems.Add("GitHub asset differs from $package ($($asset.digest), local sha256:$hash)")
            } else {
                '{0,-28} {1,-22} {2}' -f "GitHub release $tag", 'asset', "$($asset.name), same SHA-256 as dist\"
            }
        }
    }
}

if ($problems.Count) {
    ''
    "Version check FAILED for ${Version}:"
    $problems | ForEach-Object { "  - $_" }
    exit 1
}
if ($Released) { "OK: $Version is the same everywhere, tagged and released." } else {
    "OK: $Version is the same in every file and is the next version. Commit, then tag $tag."
}
