$ErrorActionPreference = "Continue"
$LAUNCHER_DIR = $PSScriptRoot

function Write-Status($msg) { Write-Host "  [..] $msg" -ForegroundColor Cyan }
function Write-OK($msg) { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [!!] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "  [XX] $msg" -ForegroundColor Red }

function Get-FileHash256($path) {
    if (-not (Test-Path $path)) { return "MISSING" }
    return (Get-FileHash -Path $path -Algorithm SHA256).Hash
}

Clear-Host
Write-Host ""
Write-Host "  +=============================================+" -ForegroundColor Magenta
Write-Host "  |   Marinara Engine   JanitorAI Launcher      |" -ForegroundColor Magenta
Write-Host "  |   v1.0 by invisibru                         |" -ForegroundColor DarkMagenta
Write-Host "  +=============================================+" -ForegroundColor Magenta
Write-Host ""

$MARINARA_DIR = ""
$possiblePaths = @(
    "$env:LOCALAPPDATA\MarinaraEngine",
    "$env:APPDATA\MarinaraEngine",
    "C:\MarinaraEngine",
    "C:\Marinara-Engine",
    "$env:USERPROFILE\MarinaraEngine",
    "$env:USERPROFILE\Desktop\MarinaraEngine"
)

foreach ($p in $possiblePaths) {
    if (Test-Path (Join-Path $p "package.json")) {
        $MARINARA_DIR = $p
        break
    }
}

if (-not $MARINARA_DIR) {
    Write-Warn "Could not auto-detect Marinara Engine location."
    Write-Host ""
    Write-Host "  Common locations:" -ForegroundColor Gray
    Write-Host "    C:\Users\YourName\AppData\Local\MarinaraEngine" -ForegroundColor Gray
    Write-Host ""
    $custom = Read-Host "  Enter your Marinara Engine folder path"
    $custom = $custom.Trim('"').Trim("'").Trim()
    if (Test-Path (Join-Path $custom "package.json")) {
        $MARINARA_DIR = $custom
    }
    else {
        Write-Err "No package.json found at: $custom"
        Read-Host "Press Enter to exit"
        exit 1
    }
}

Write-OK "Found Marinara Engine at: $MARINARA_DIR"

$TARGET_ROUTES = Join-Path $MARINARA_DIR "packages\server\src\routes\bot-browser.routes.ts"
$TARGET_VIEW = Join-Path $MARINARA_DIR "packages\client\src\components\bot-browser\BotBrowserView.tsx"
$PATCHED_ROUTES = Join-Path $LAUNCHER_DIR "bot-browser.routes.patched.ts"
$PATCHED_VIEW = Join-Path $LAUNCHER_DIR "BotBrowserView.patched.tsx"
$HASH_FILE = Join-Path $LAUNCHER_DIR "known-hashes.txt"

if (-not (Test-Path $PATCHED_ROUTES)) {
    Write-Err "Missing file: bot-browser.routes.patched.ts"
    Read-Host "Press Enter to exit"
    exit 1
}
if (-not (Test-Path $PATCHED_VIEW)) {
    Write-Err "Missing file: BotBrowserView.patched.tsx"
    Read-Host "Press Enter to exit"
    exit 1
}
if (-not (Test-Path $TARGET_ROUTES)) {
    Write-Err "Cannot find: $TARGET_ROUTES"
    Write-Err "Your Marinara install may be corrupted or a different version."
    Read-Host "Press Enter to exit"
    exit 1
}
if (-not (Test-Path $TARGET_VIEW)) {
    Write-Err "Cannot find: $TARGET_VIEW"
    Write-Err "Your Marinara install may be corrupted or a different version."
    Read-Host "Press Enter to exit"
    exit 1
}

$nodeCheck = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCheck) {
    Write-Err "Node.js not found. Install Node.js 20+ from https://nodejs.org"
    Read-Host "Press Enter to exit"
    exit 1
}
$nodeVer = node -v
Write-OK "Node.js: $nodeVer"

Push-Location $MARINARA_DIR

$pnpmVersion = "10.30.3"
try {
    $pkgJson = Get-Content "package.json" -Raw | ConvertFrom-Json
    if ($pkgJson.packageManager) {
        $pnpmVersion = $pkgJson.packageManager.Split("@")[1]
    }
}
catch {}

$hasPnpm = Get-Command pnpm -ErrorAction SilentlyContinue
if (-not $hasPnpm) {
    Write-Status "Installing pnpm $pnpmVersion..."
    $hasCorepack = Get-Command corepack -ErrorAction SilentlyContinue
    if ($hasCorepack) {
        corepack enable 2>$null
        corepack prepare "pnpm@$pnpmVersion" --activate 2>&1 | Out-Null
    }
    else {
        npm install -g "pnpm@$pnpmVersion" 2>&1 | Out-Null
    }
}
else {
    $currentPnpm = pnpm -v 2>$null
    if ($currentPnpm -ne $pnpmVersion) {
        Write-Status "Aligning pnpm to $pnpmVersion..."
        $hasCorepack = Get-Command corepack -ErrorAction SilentlyContinue
        if ($hasCorepack) {
            corepack enable 2>$null
            corepack prepare "pnpm@$pnpmVersion" --activate 2>&1 | Out-Null
        }
        else {
            npm install -g "pnpm@$pnpmVersion" 2>&1 | Out-Null
        }
    }
}
Write-OK "pnpm $pnpmVersion ready"

$needsFullRebuild = $false
$skipPatch = $false
$updated = $false

if (Test-Path (Join-Path $MARINARA_DIR ".git")) {
    Write-Status "Checking for updates..."

    $oldHead = git rev-parse HEAD 2>$null

    $stashed = $false
    git diff --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        git stash push -q -m "janitor-launcher-auto-stash" 2>$null
        $stashed = $true
    }

    git pull 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Git pull failed. Continuing with current version."
        if ($stashed) { git stash pop -q 2>$null }
    }
    else {
        $newHead = git rev-parse HEAD 2>$null

        if ($oldHead -ne $newHead) {
            Write-OK "Updated to latest version!"
            $updated = $true
            $needsFullRebuild = $true

            if ($stashed) {
                git stash drop -q 2>$null
                $stashed = $false
            }

            Write-Status "Reinstalling dependencies..."
            pnpm install 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }

            Write-Status "Cleaning old builds..."
            $dirsToClean = @("packages\shared\dist", "packages\server\dist", "packages\client\dist")
            foreach ($d in $dirsToClean) {
                $fullPath = Join-Path $MARINARA_DIR $d
                if (Test-Path $fullPath) { Remove-Item $fullPath -Recurse -Force }
            }
            $filesToClean = @("packages\shared\tsconfig.tsbuildinfo", "packages\server\tsconfig.tsbuildinfo", "packages\client\tsconfig.tsbuildinfo")
            foreach ($f in $filesToClean) {
                $fullPath = Join-Path $MARINARA_DIR $f
                if (Test-Path $fullPath) { Remove-Item $fullPath -Force }
            }
        }
        else {
            Write-OK "Already up to date."
            if ($stashed) { git stash pop -q 2>$null }
        }
    }
}
else {
    Write-Warn "Not a git repo - skipping update."
}

if (-not (Test-Path (Join-Path $MARINARA_DIR "node_modules"))) {
    Write-Status "Installing dependencies (first run)..."
    pnpm install 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    $needsFullRebuild = $true
}

Write-Status "Checking file compatibility..."

$currentRoutesHash = Get-FileHash256 $TARGET_ROUTES
$currentViewHash = Get-FileHash256 $TARGET_VIEW

if (Test-Path $HASH_FILE) {
    $lines = Get-Content $HASH_FILE
    $knownRoutesHash = ""
    $knownViewHash = ""
    if ($lines.Count -ge 1) { $knownRoutesHash = $lines[0] }
    if ($lines.Count -ge 2) { $knownViewHash = $lines[1] }

    $routesChanged = ($currentRoutesHash -ne $knownRoutesHash)
    $viewChanged = ($currentViewHash -ne $knownViewHash)

    if ($routesChanged -or $viewChanged) {
        Write-Host ""
        Write-Err "============================================"
        Write-Err "  UPSTREAM FILES HAVE CHANGED!"
        Write-Err "============================================"
        Write-Host ""
        if ($routesChanged) { Write-Err "  Changed: bot-browser.routes.ts" }
        if ($viewChanged) { Write-Err "  Changed: BotBrowserView.tsx" }
        Write-Host ""
        Write-Warn "The JanitorAI patch may not work with the updated files."
        Write-Host ""
        Write-Host "  [1] Launch WITHOUT JanitorAI (safe)" -ForegroundColor White
        Write-Host "  [2] Force patch anyway (may break!)" -ForegroundColor Yellow
        Write-Host "  [3] I updated the patch files - reset hashes" -ForegroundColor Cyan
        Write-Host "  [4] Exit" -ForegroundColor Gray
        Write-Host ""
        $choice = Read-Host "  Enter choice (1/2/3/4)"

        if ($choice -eq "1") {
            Write-Status "Launching without JanitorAI patch..."
            $skipPatch = $true
        }
        elseif ($choice -eq "2") {
            Write-Warn "Force-patching. If it breaks, run the official start.bat to fix."
        }
        elseif ($choice -eq "3") {
            Write-Status "Resetting hashes..."
            Set-Content -Path $HASH_FILE -Value @($currentRoutesHash, $currentViewHash) -Encoding UTF8
            Write-OK "Done. Re-run this launcher."
            Read-Host "Press Enter to exit"
            Pop-Location
            exit 0
        }
        else {
            Pop-Location
            exit 0
        }
    }
    else {
        Write-OK "Files compatible - safe to patch!"
    }
}
else {
    Write-Status "First run - saving file signatures..."
    Set-Content -Path $HASH_FILE -Value @($currentRoutesHash, $currentViewHash) -Encoding UTF8
    Write-OK "Baseline saved."
}

if (-not $skipPatch) {
    Write-Host ""
    Write-Status "Patching bot-browser.routes.ts (adding JanitorAI routes)..."
    Copy-Item $PATCHED_ROUTES $TARGET_ROUTES -Force
    Write-OK "Server routes patched!"

    Write-Status "Patching BotBrowserView.tsx (adding JanitorAI provider)..."
    Copy-Item $PATCHED_VIEW $TARGET_VIEW -Force
    Write-OK "Client view patched!"
    Write-Host ""

    $serverDist = Join-Path $MARINARA_DIR "packages\server\dist"
    $clientDist = Join-Path $MARINARA_DIR "packages\client\dist"
    if (Test-Path $serverDist) { Remove-Item $serverDist -Recurse -Force }
    if (Test-Path $clientDist) { Remove-Item $clientDist -Recurse -Force }
    $tsbFiles = @("packages\server\tsconfig.tsbuildinfo", "packages\client\tsconfig.tsbuildinfo")
    foreach ($f in $tsbFiles) {
        $fullPath = Join-Path $MARINARA_DIR $f
        if (Test-Path $fullPath) { Remove-Item $fullPath -Force }
    }
    $needsFullRebuild = $true
}

$sharedDist = Join-Path $MARINARA_DIR "packages\shared\dist"
$serverDist = Join-Path $MARINARA_DIR "packages\server\dist"
$clientDist = Join-Path $MARINARA_DIR "packages\client\dist"

$defaultsJs = Join-Path $sharedDist "constants\defaults.js"
if (Test-Path $defaultsJs) {
    $sourceVer = ""
    $distVer = ""
    try {
        $sourceVer = (Get-Content (Join-Path $MARINARA_DIR "package.json") -Raw | ConvertFrom-Json).version
    }
    catch {}
    try {
        $jsPath = $defaultsJs -replace [regex]::Escape('\'), '/'
        $distVer = node -e "try{const m=require('$jsPath');console.log(m.APP_VERSION)}catch(e){}" 2>$null
    }
    catch {}

    if ($sourceVer -and $distVer -and ($sourceVer -ne $distVer)) {
        Write-Warn "Version mismatch: source v$sourceVer vs dist v$distVer"
        Write-Status "Forcing full rebuild..."
        foreach ($d in @($sharedDist, $serverDist, $clientDist)) {
            if (Test-Path $d) { Remove-Item $d -Recurse -Force }
        }
        $needsFullRebuild = $true
    }
}

if ((-not (Test-Path $sharedDist)) -or $needsFullRebuild) {
    Write-Status "Building shared types..."
    pnpm build:shared 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
}

if (-not (Test-Path $serverDist)) {
    Write-Status "Building server..."
    pnpm build:server 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
}

if (-not (Test-Path $clientDist)) {
    Write-Status "Building client..."
    pnpm build:client 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
}

Write-OK "Build complete!"

$envFile = Join-Path $MARINARA_DIR ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and (-not $line.StartsWith("#")) -and $line.Contains("=")) {
            $eqIndex = $line.IndexOf("=")
            $key = $line.Substring(0, $eqIndex).Trim()
            $val = $line.Substring($eqIndex + 1).Trim()
            [Environment]::SetEnvironmentVariable($key, $val, "Process")
        }
    }
}

$env:NODE_ENV = "production"
if (-not $env:PORT) { $env:PORT = "7860" }
if (-not $env:HOST) { $env:HOST = "0.0.0.0" }

$protocol = "http"
if ($env:SSL_CERT -and $env:SSL_KEY) { $protocol = "https" }

$listenUrl = "${protocol}://localhost:$($env:PORT)"

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "    Starting Marinara Engine" -ForegroundColor Green
Write-Host "    $listenUrl" -ForegroundColor Green
if (-not $skipPatch) {
    Write-Host "    JanitorAI: ENABLED" -ForegroundColor Magenta
}
else {
    Write-Host "    JanitorAI: DISABLED (needs update)" -ForegroundColor Yellow
}
Write-Host "    Press Ctrl+C to stop" -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""

$autoOpen = $true
if ($env:AUTO_OPEN_BROWSER) {
    if ($env:AUTO_OPEN_BROWSER -match "^(0|false|no|off)$") { $autoOpen = $false }
}
if ($autoOpen) {
    Start-Job -ScriptBlock {
        Start-Sleep -Seconds 4
        Start-Process $using:listenUrl
    } | Out-Null
}

Set-Location (Join-Path $MARINARA_DIR "packages\server")
node dist/index.js

Pop-Location
Write-Host ""
Write-Err "Server exited unexpectedly. Check the error above."
Read-Host "Press Enter to exit"
