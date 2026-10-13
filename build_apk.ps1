# Builds the release APK with the Neon connection string compiled in, and
# pointed at backend/api - most of the app (registration, wallet,
# prescriptions, orders, the agent portal) has been migrated onto backend/api
# and reads nothing real without BACKEND_API_BASE_URL compiled in; without it
# BackendHttp.isConfigured is false at runtime and every one of those
# features silently no-ops, same as an unset DATABASE_URL leaves the
# catalogue empty rather than erroring.
#
#   powershell -ExecutionPolicy Bypass -File build_apk.ps1
#
# The Neon connection string is NOT passed via --dart-define: it contains
# '&', and flutter.bat runs under cmd.exe on Windows, which treats '&' on the
# command line as a statement separator and truncates the value. Instead it
# lives in the git-ignored lib/data/neon/neon_secret.dart, generated from
# .env by the step below, and is just compiled in.
#
# BACKEND_API_BASE_URL is public, not a secret (see vercel-build.sh's own
# doc) - this is simply shield_backend's own deployed URL, hardcoded here
# the same way the web build instead reads it from a Vercel project env var.
# Update this if the backend is ever redeployed to a different domain.
#
# NOTE: keep every string in this file plain ASCII. Windows PowerShell 5.1
# read this file under the system codepage rather than UTF-8 at least once
# before, and a non-ASCII character (an em dash) inside a double-quoted,
# variable-interpolated string broke the parser outright ("Unexpected token"
# / "string is missing the terminator") rather than just printing oddly the
# way the same character does inside a single-quoted literal.
#
# SENTRY_DSN has no '&', so it IS passed via --dart-define, read straight out
# of the same .env gen_neon_secret.dart already requires. Blank (no line, or
# no .env yet) just builds with Sentry disabled - see docs/sentry.md.
#
# Always starts with `flutter clean`, and verifies BACKEND_API_BASE_URL
# actually made it into the compiled code afterward. Confirmed live on the
# root app's own build (2026-10-13): a plain `flutter build apk` after an
# earlier build can silently keep the previous build's compiled Dart code -
# including a stale or absent BACKEND_API_BASE_URL - with no error or
# non-zero exit code, reproduced by unzipping the resulting APK and
# checking libapp.so directly for the URL string. Do not remove either step
# for a faster build - a release that quietly ships the wrong backend (or
# none) costs far more than a few extra minutes here to even notice.

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$BackendApiBaseUrl = 'https://shieldbackend.vercel.app'

if (Test-Path 'tool/gen_neon_secret.dart') {
    Write-Host 'Generating lib/data/neon/neon_secret.dart from .env ...' -ForegroundColor Cyan
    dart run tool/gen_neon_secret.dart
} elseif (Test-Path 'lib/data/neon/neon_secret.dart') {
    Write-Host 'tool/gen_neon_secret.dart no longer exists - reusing the already-generated lib/data/neon/neon_secret.dart as-is.' -ForegroundColor Yellow
} else {
    Write-Host 'Neither tool/gen_neon_secret.dart nor lib/data/neon/neon_secret.dart exist - copy lib/data/neon/neon_secret.example.dart there first (or generate a real one) before building.' -ForegroundColor Red
    exit 1
}

$SentryDsn = ''
if (Test-Path '.env') {
    $line = Select-String -Path '.env' -Pattern '^\s*SENTRY_DSN\s*=' | Select-Object -Last 1
    if ($line) {
        $SentryDsn = ($line.Line -split '=', 2)[1].Trim().Trim('"').Trim("'")
    }
}

Write-Host 'Cleaning previous build output (required - see this script''s own comment on why) ...' -ForegroundColor Cyan
flutter clean

Write-Host "Building release APK against $BackendApiBaseUrl (one build at a time - close any other flutter build/run) ..." -ForegroundColor Cyan
flutter build apk --release --dart-define=BACKEND_API_BASE_URL=$BackendApiBaseUrl --dart-define=SENTRY_DSN=$SentryDsn

$ApkPath = 'build\app\outputs\flutter-apk\app-release.apk'

# Self-check: confirm BACKEND_API_BASE_URL actually made it into the
# compiled code, rather than trusting that `flutter build` exiting 0 means
# it did - see this script's own comment above on why that trust already
# failed once. Unzips the APK into a throwaway temp folder and greps the
# compiled Dart snapshot (libapp.so) for the literal URL string.
Write-Host 'Verifying the backend URL actually made it into the build ...' -ForegroundColor Cyan
$CheckDir = Join-Path $env:TEMP "shield-apk-check-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $CheckDir -Force | Out-Null
try {
    $ZipCopy = Join-Path $CheckDir 'app-release.zip'
    Copy-Item $ApkPath $ZipCopy
    Expand-Archive -Path $ZipCopy -DestinationPath $CheckDir -Force
    $LibApp = Get-ChildItem -Path $CheckDir -Recurse -Filter 'libapp.so' | Select-Object -First 1
    $Found = $false
    if ($LibApp) {
        $Bytes = [System.IO.File]::ReadAllBytes($LibApp.FullName)
        # ISO-8859-1, not Encoding.Latin1 - the latter is a .NET 5+-only
        # static property and is $null under Windows PowerShell 5.1's .NET
        # Framework runtime (confirmed: silently null, not an error, until
        # .GetString() throws). Purely a byte-safe 1:1 decode for finding
        # an ASCII URL substring in binary data.
        $Text = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($Bytes)
        $Found = $Text.Contains($BackendApiBaseUrl)
    }
    if (-not $Found) {
        Write-Host ''
        Write-Host "BUILD VERIFICATION FAILED: $BackendApiBaseUrl was not found in the compiled" -ForegroundColor Red
        Write-Host 'app. Installing this APK will reproduce "Verification is unavailable on' -ForegroundColor Red
        Write-Host 'this device right now." Do not distribute this build.' -ForegroundColor Red
        exit 1
    }
    Write-Host 'Confirmed: the backend URL is present in the compiled app.' -ForegroundColor Green
} finally {
    Remove-Item -Path $CheckDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "Done: $ApkPath" -ForegroundColor Green
Write-Host 'Uninstall the app on the phone first, then install this. "Get OTP" on'
Write-Host 'the sign-in screen must actually text a code - "Verification is'
Write-Host 'unavailable on this device right now" means BACKEND_API_BASE_URL'
Write-Host 'above is wrong or the backend is unreachable, not a code problem.'
