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

Write-Host "Building release APK against $BackendApiBaseUrl (one build at a time - close any other flutter build/run) ..." -ForegroundColor Cyan
flutter build apk --release --dart-define=BACKEND_API_BASE_URL=$BackendApiBaseUrl --dart-define=SENTRY_DSN=$SentryDsn

Write-Host ''
Write-Host 'Done: build/app/outputs/flutter-apk/app-release.apk' -ForegroundColor Green
Write-Host 'Uninstall the app on the phone first, then install this. The login'
Write-Host 'screen must show a green "Database connected" line.'
