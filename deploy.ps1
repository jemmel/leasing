<#
.SYNOPSIS
  Leasing-Kilometerrechner nach Cloudflare Pages (leasing.janemmel.de).

.DESCRIPTION
  Kopiert index.html, manifest.json und service-worker.js nach _site/, legt _headers dazu und lädt _site/ mit
  wrangler hoch. Beim ersten Lauf legt es das Pages-Projekt an, hängt die Domain an und setzt den
  CNAME in der Zone janemmel.de. Spätere Läufe überspringen, was schon da ist.

  Das Cloudflare-Token kommt aus $env:CLOUDFLARE_API_TOKEN, sonst aus .env in diesem Ordner
  (cloudflare_api_token=...). Es wird nie ausgegeben.

.EXAMPLE
  ./deploy.ps1 -DryRun      # _site/ bauen und zeigen, was hochginge
  ./deploy.ps1              # bauen, hochladen
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Branch = 'main'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$site = Join-Path $root '_site'
$project = 'leasing-janemmel-de'
$domain = 'leasing.janemmel.de'
$zoneName = 'janemmel.de'
$accountId = '2b6304381678742e4b09808de636f58f'

# ── Bauen ──
Remove-Item -Recurse -Force $site -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $site | Out-Null
foreach ($f in 'index.html', 'manifest.json', 'service-worker.js') { Copy-Item (Join-Path $root $f) $site }
# Die App lädt nur eigene Dateien (Manifest, Service Worker) und sendet nichts; die CSP hält das fest.
# Den Service Worker nie aus dem Cache liefern, sonst kommen neue Versionen nicht an.
@'
/*
  Content-Security-Policy: default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; manifest-src 'self'; worker-src 'self'; connect-src 'self'; form-action 'none'; base-uri 'none'; frame-ancestors 'none'
  Referrer-Policy: no-referrer
  X-Content-Type-Options: nosniff
  Permissions-Policy: camera=(), microphone=(), geolocation=(), interest-cohort=()

/service-worker.js
  Cache-Control: no-cache
'@ | Set-Content -NoNewline -Encoding utf8 (Join-Path $site '_headers')

$files = @(Get-ChildItem -Path $site -Recurse -File)
Write-Host "Hochzuladen: $($files.Count) Dateien" -ForegroundColor Cyan
if ($DryRun) { Write-Host 'Probelauf, nichts hochgeladen.' -ForegroundColor Cyan; return }

# ── Zugang ──
$token = $env:CLOUDFLARE_API_TOKEN
if (-not $token) {
    $envFile = Join-Path $root '.env'
    if (-not (Test-Path $envFile)) { throw 'Keine .env gefunden (erwartet cloudflare_api_token=...)' }
    $token = (Get-Content $envFile |
        Where-Object { $_ -match '^\s*cloudflare_api_token\s*=' } |
        Select-Object -First 1) -replace '^\s*cloudflare_api_token\s*=\s*', '' -replace '^["'']|["'']$', ''
}
if (-not $token -or -not $token.Trim()) { throw 'cloudflare_api_token fehlt oder ist leer' }
$token = $token.Trim()

$api = 'https://api.cloudflare.com/client/v4'
$headers = @{ Authorization = "Bearer $token" }
function Invoke-Cf([string]$Method, [string]$Path, $Body) {
    $req = @{ Method = $Method; Uri = "$api$Path"; Headers = $headers; SkipHttpErrorCheck = $true }
    if ($Body) { $req.Body = ($Body | ConvertTo-Json -Depth 5); $req.ContentType = 'application/json' }
    Invoke-RestMethod @req
}

# ── Projekt ──
$found = Invoke-Cf GET "/accounts/$accountId/pages/projects/$project"
if (-not $found.success) {
    $made = Invoke-Cf POST "/accounts/$accountId/pages/projects" @{ name = $project; production_branch = $Branch }
    if (-not $made.success) { throw "Pages-Projekt nicht angelegt: $(($made.errors | ForEach-Object message) -join '; ')" }
    Write-Host "Pages-Projekt $project angelegt" -ForegroundColor Green
}

# ── Hochladen ──
$tokenWasSet = [bool]$env:CLOUDFLARE_API_TOKEN
$env:CLOUDFLARE_API_TOKEN = $token
$env:CLOUDFLARE_ACCOUNT_ID = $accountId
Push-Location $root
try {
    npx --yes wrangler@4.139.0 pages deploy $site --project-name $project --branch $Branch --commit-dirty=true --commit-message "Leasing-Kilometerrechner"
    if ($LASTEXITCODE -ne 0) { throw "wrangler endete mit $LASTEXITCODE" }
}
finally {
    Pop-Location
    if (-not $tokenWasSet) { $env:CLOUDFLARE_API_TOKEN = $null }
}

# ── Domain ──
$domains = Invoke-Cf GET "/accounts/$accountId/pages/projects/$project/domains"
if (-not $domains.success) { throw "Domains nicht lesbar: $(($domains.errors | ForEach-Object message) -join '; ')" }
if (-not ($domains.result | Where-Object name -eq $domain)) {
    $added = Invoke-Cf POST "/accounts/$accountId/pages/projects/$project/domains" @{ name = $domain }
    if (-not $added.success) { throw "Domain $domain nicht angehängt: $(($added.errors | ForEach-Object message) -join '; ')" }
    Write-Host "Domain $domain angehängt" -ForegroundColor Green
}

$zone = (Invoke-Cf GET "/zones?name=$zoneName").result | Select-Object -First 1
if (-not $zone) { throw "Zone $zoneName nicht lesbar" }
$target = "$project.pages.dev"
$record = (Invoke-Cf GET "/zones/$($zone.id)/dns_records?type=CNAME&name=$domain").result | Select-Object -First 1
if (-not $record) {
    $dns = Invoke-Cf POST "/zones/$($zone.id)/dns_records" @{ type = 'CNAME'; name = $domain; content = $target; proxied = $true; ttl = 1 }
    if (-not $dns.success) { throw "DNS $domain nicht angelegt: $(($dns.errors | ForEach-Object message) -join '; ')" }
    Write-Host "DNS $domain -> $target angelegt" -ForegroundColor Green
}
elseif ($record.content -ne $target) {
    Write-Warning "DNS $domain zeigt auf $($record.content), nicht auf $target"
}

Write-Host "Fertig: https://$domain" -ForegroundColor Green
