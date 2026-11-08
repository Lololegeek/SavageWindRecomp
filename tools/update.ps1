<#
Savage Wind updater (Windows): puts a new version of Savage Wind over an install that already has its game files set
up, without setting them up again.

What it changes: only the files of the release (savagewind.exe, its DLLs, the configuration exe, swgen/, zig/,
gamelib-src/, the fonts, colour-luts/...). What it never touches: the game files copied at setup (extracted/, ...),
the game code built from them (swgame.dll and its .id), cache/ (shaders, pipelines, cache/gamecode/), saves,
settings, logs, your own LUTs. Nothing is deleted outside the release's own folders (swgen/, zig/, gamelib-src/,
colour-luts/, mirrored so that no file of an older version is left there).

When the new version's game code differs (its id, runtime/gamelib.h), the start screen builds it again from the files
copied already (SAVAGEWIND_AUTO_REBUILD=1, set when this script starts the game): no copy, no extraction, and every
piece of game code whose C didn't change comes from cache/gamecode/, so it is much quicker than the first setup.

usage (from the install folder, or with -InstallDir):
  "Update Savage Wind.bat"                         the newest release of the default repository
  update.ps1 -Repo Revivedx/SavageWindRecomp       another repository's releases (owner/name)
  update.ps1 -Stable                               releases only, no pre-releases
  update.ps1 -Zip SavageWind-0.4.2-windows.zip     a release zip already downloaded
  update.ps1 -From "C:\src\SavageWindRecomp\build\dist\Savage Wind"   a folder built with `make dist`
  update.ps1 -Check                                only says whether an update is there
  update.ps1 -NoLaunch                             doesn't start Savage Wind afterwards
  update.ps1 -Backup                               keeps the replaced files in update-backup\<old version>\
#>
param(
    [string]$InstallDir = "",
    [string]$Repo = "Lololegeek/SavageWindRecomp",
    [string]$FallbackRepo = "Revivedx/SavageWindRecomp",
    [string]$Zip = "",
    [string]$From = "",
    [switch]$Stable,
    [switch]$Check,
    [switch]$NoLaunch,
    [switch]$Backup,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # (Invoke-WebRequest is many times slower with its progress bar)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Say($msg, $color = "Gray") { Write-Host "[update] $msg" -ForegroundColor $color }
function Fail($msg) { Say $msg "Red"; if (-not $env:SAVAGEWIND_UPDATE_NOPAUSE) { Read-Host "Press Enter to close" | Out-Null }; exit 1 }

# ------------------------------------------------------------------ the install
if (-not $InstallDir) { $InstallDir = $PSScriptRoot }
$InstallDir = (Resolve-Path -LiteralPath $InstallDir).Path
$exe = Join-Path $InstallDir "savagewind.exe"
if (-not (Test-Path -LiteralPath $exe)) { Fail "No savagewind.exe in $InstallDir (run this from the Savage Wind folder, or pass -InstallDir)." }

# The version installed: the one this script wrote last, else the one in the exe (launcher.mm SAVAGEWIND_VERSION)
$verFile = Join-Path $InstallDir "savagewind-version.txt"
function Installed-Version {
    if (Test-Path -LiteralPath $verFile) { return (Get-Content -LiteralPath $verFile -TotalCount 1).Trim() }
    try {
        $bytes = [IO.File]::ReadAllBytes($exe)
        $text = [Text.Encoding]::ASCII.GetString($bytes)
        # The exe also holds other x.y.z strings (the game's own "1.9.0"), and the compiler can pack the version right
        # after other constants with no NUL in between ("...dda70.4.1-alpha.4"), so: the string the linker places
        # before "/" and "file://" (the updater's own strings), with a one-digit major.
        $m = [regex]::Match($text, "(\d\.\d+\.\d+(?:-[A-Za-z0-9.]+)?)\x00/\x00file://")
        if ($m.Success) { return $m.Groups[1].Value }
    } catch {}
    # The startup log's first line: "[savagewind] Savage Wind <version> (commit ..."
    $log = Join-Path $InstallDir "savagewind.log"
    try {
        if (Test-Path -LiteralPath $log) {
            $m = [regex]::Match((Get-Content -LiteralPath $log -TotalCount 5) -join "`n", "Savage Wind (\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?) \(commit")
            if ($m.Success) { return $m.Groups[1].Value }
        }
    } catch {}
    return "unknown"
}
$current = Installed-Version
Say "Savage Wind in $InstallDir, version $current"

# Compares two version strings like 0.4.1-alpha.4 (a pre-release sorts before its release)
function Version-Key($v) {
    $v = $v.TrimStart("v", "V")
    $main, $pre = $v.Split("-", 2)
    $nums = @($main.Split(".") | ForEach-Object { [int]($_ -replace "\D", "0") })
    while ($nums.Count -lt 3) { $nums += 0 }
    $preKey = if ($pre) { "0" + (($pre.Split(".") | ForEach-Object { if ($_ -match "^\d+$") { "{0:D6}" -f [int]$_ } else { $_ } }) -join ".") } else { "1" }
    return ("{0:D6}.{1:D6}.{2:D6}." -f $nums[0], $nums[1], $nums[2]) + $preKey
}

# ------------------------------------------------------------------ the new version
$work = Join-Path ([IO.Path]::GetTempPath()) ("savagewind-update-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $newVersion = ""
    if ($From) {
        $src = (Resolve-Path -LiteralPath $From).Path
        $newVersion = "local build"
    } else {
        if (-not $Zip) {
            function Find-Release($repo) {
                $headers = @{ "User-Agent" = "SavageWind-Updater"; "Accept" = "application/vnd.github+json" }
                if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN" }
                try { $list = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases?per_page=30" -Headers $headers }
                catch { Say "Couldn't read the releases of ${repo}: $($_.Exception.Message)" "Yellow"; return $null }
                foreach ($r in $list) {
                    if ($r.draft -or ($Stable -and $r.prerelease)) { continue }
                    $asset = $r.assets | Where-Object { $_.name -like "SavageWind-*-windows.zip" } | Select-Object -First 1
                    if ($asset) { return @{ repo = $repo; tag = $r.tag_name; asset = $asset } }
                }
                return $null
            }
            $rel = Find-Release $Repo
            if (-not $rel -and $FallbackRepo -and $FallbackRepo -ne $Repo) {
                Say "No Windows release in ${Repo}: looking at $FallbackRepo" "Yellow"
                $rel = Find-Release $FallbackRepo
            }
            if (-not $rel) { Fail "No Windows release found." }
            $newVersion = $rel.tag.TrimStart("v", "V")
            Say "Newest release: $newVersion ($($rel.repo), $([math]::Round($rel.asset.size / 1MB)) MB)"
            if (-not $Force -and $current -ne "unknown" -and (Version-Key $newVersion) -le (Version-Key $current)) {
                Say "Already up to date." "Green"
                if (-not $NoLaunch -and -not $Check) { Start-Process -FilePath $exe -WorkingDirectory $InstallDir }
                exit 0
            }
            if ($Check) { Say "Update available: $current -> $newVersion" "Cyan"; exit 0 }
            $Zip = Join-Path $work $rel.asset.name
            Say "Downloading $($rel.asset.browser_download_url)"
            Invoke-WebRequest -Uri $rel.asset.browser_download_url -OutFile $Zip -UseBasicParsing -Headers @{ "User-Agent" = "SavageWind-Updater" }
        } elseif ($Check) { Say "-Check needs a release from GitHub, not -Zip." "Yellow"; exit 0 }
        $Zip = (Resolve-Path -LiteralPath $Zip).Path
        if (-not $newVersion) { $m = [regex]::Match([IO.Path]::GetFileName($Zip), "SavageWind-(.+)-windows\.zip"); $newVersion = if ($m.Success) { $m.Groups[1].Value } else { "zip" } }
        $unz = Join-Path $work "unzip"
        Say "Extracting the release"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($Zip, $unz)
        # (the zip's top folder is "Savage Wind/": Makefile dist)
        $src = Join-Path $unz "Savage Wind"
        if (-not (Test-Path -LiteralPath $src)) { $src = (Get-ChildItem -LiteralPath $unz -Directory | Select-Object -First 1).FullName }
    }
    if (-not $src -or -not (Test-Path -LiteralPath (Join-Path $src "savagewind.exe"))) { Fail "The new version has no savagewind.exe." }
    # Never a release with game code or game files in it: they are the player's own, built on this PC
    foreach ($own in @("swgame.dll", "swgame.so", "extracted", "saves", "cache")) {
        if (Test-Path -LiteralPath (Join-Path $src $own)) { Fail "The new version has $own in it: not a Savage Wind release, nothing changed." }
    }

    # ------------------------------------------------------------------ Savage Wind closed
    $running = Get-Process -Name "savagewind", "savagewind-config", "Savage Wind Configuration" -ErrorAction SilentlyContinue |
               Where-Object { $_.Path -and $_.Path.StartsWith($InstallDir, [StringComparison]::OrdinalIgnoreCase) }
    if ($running) {
        Say "Savage Wind is running: close it to update (waiting up to 60 s)..." "Yellow"
        $running | Wait-Process -Timeout 60 -ErrorAction SilentlyContinue
        if ($running | Where-Object { -not $_.HasExited }) { Fail "Savage Wind is still running: nothing changed." }
    }

    # ------------------------------------------------------------------ copy
    if ($Backup) {
        $bak = Join-Path $InstallDir ("update-backup\" + ($current -replace '[\\/:*?"<>|]', "_"))
        Say "Keeping the replaced files in $bak"
        Get-ChildItem -LiteralPath $src -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($src.Length).TrimStart("\")
            $old = Join-Path $InstallDir $rel
            if (Test-Path -LiteralPath $old) {
                $dst = Join-Path $bak $rel
                New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
                Copy-Item -LiteralPath $old -Destination $dst -Force
            }
        }
    }
    # The release's own folders: mirrored (robocopy /MIR deletes what an older version left there and nothing else)
    $mirrored = @("swgen", "zig", "gamelib-src", "colour-luts")
    foreach ($d in $mirrored) {
        $s = Join-Path $src $d
        if (-not (Test-Path -LiteralPath $s)) { continue }
        Say "Updating $d\"
        & robocopy $s (Join-Path $InstallDir $d) /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { Fail "Copying $d failed (robocopy $LASTEXITCODE). Run the update again." }
    }
    # Everything else of the release: copied over, nothing deleted
    Say "Updating savagewind.exe and its files"
    & robocopy $src $InstallDir /E /XD ($mirrored | ForEach-Object { Join-Path $src $_ }) /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail "Copying the files failed (robocopy $LASTEXITCODE). Run the update again." }
    Set-Content -LiteralPath $verFile -Value $newVersion -Encoding ASCII
    # A copy of this updater next to the exe, for the next time (the release may have a newer one)
    foreach ($f in @("update.ps1", "Update Savage Wind.bat")) {
        if (-not (Test-Path -LiteralPath (Join-Path $src $f)) -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot $f)) -and $PSScriptRoot -ne $InstallDir) {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $f) -Destination $InstallDir -Force
        }
    }
    Say "Updated: $current -> $newVersion" "Green"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------ start
if (-not $NoLaunch) {
    Say "Starting Savage Wind (the game code is built again if this version needs it: no setup, no copy)"
    $env:SAVAGEWIND_AUTO_REBUILD = "1"
    Start-Process -FilePath $exe -WorkingDirectory $InstallDir
}
