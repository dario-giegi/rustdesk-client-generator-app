<#
.SYNOPSIS
  Compila un client RustDesk per Windows MSVC personalizzato.

.DESCRIPTION
  1. Checkout del codice generator e del repo ufficiale RustDesk
  2. Installa dipendenze native con vcpkg
  3. Applica la configurazione JSON
  4. Compila Flutter UI e backend Rust
  5. Genera eseguibile e package

.PARAMETER ConfigJson
  Path al file config.json generato dalla UI del generator.

.PARAMETER OutputDir
  Directory di destinazione per artefatti (default: .\output).

.EXAMPLE
  .\build-windows.ps1 -ConfigJson .\config.json -OutputDir .\output
#>

param(
  [Parameter(Mandatory=$true)]
  [string]$ConfigJson,

  [Parameter(Mandatory=$false)]
  [string]$OutputDir = ".\output"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Inizio build RustDesk client Windows ==="

# 1. Controlli preliminari
if (-not (Test-Path $ConfigJson)) {
  Write-Error "File di configurazione non trovato: $ConfigJson"
  exit 1
}

# 2. Checkout o aggiornamento del codice sorgente
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $scriptDir

if (-not (Test-Path ".\rustdesk")) {
  Write-Host "Clono repository ufficiale RustDesk..."
  git clone https://github.com/rustdesk/rustdesk.git
} else {
  Write-Host "Aggiorno repository RustDesk..."
  Push-Location .\rustdesk
  git fetch origin
  git reset --hard origin/master
  Pop-Location
}

# 3. Imposta toolchain Rust
Write-Host "Imposto target MSVC..."
rustup target add x86_64-pc-windows-msvc

# 4. Installa dipendenze native via vcpkg
Write-Host "Eseguo vcpkg install..."
if (-not $env:VCPKG_ROOT) {
  Write-Error "Variabile VCPKG_ROOT non impostata. Imposta il path della cartella vcpkg."
  exit 1
}
Push-Location .\rustdesk
Copy-Item "$scriptDir\vcpkg.json" -Destination . -Force
& "$env:VCPKG_ROOT\vcpkg.exe" install --triplet x64-windows-static

# 5. Applica configurazione JSON nel source
Write-Host "Applico configurazione JSON..."
New-Item -ItemType Directory -Path ".\src\ui" -Force | Out-Null
Copy-Item $ConfigJson -Destination ".\src\ui\config.json" -Force

# 6. Compila Flutter UI
Write-Host "Compilazione Flutter UI..."
Push-Location .\flutter
flutter pub get
flutter build windows --release
Pop-Location

# 7. Genera codice bridge Rust↔Flutter (se presente)
if (Test-Path ".\src\flutter_ffi.rs") {
  Write-Host "Generazione flutter_rust_bridge..."
  cargo install flutter_rust_bridge_codegen --version 1.80.1 --features "uuid" -q
  flutter_rust_bridge_codegen --rust-input src/flutter_ffi.rs --dart-output flutter/lib/generated_bridge.dart
}

# 8. Compila backend Rust
Write-Host "Compilo backend Rust..."
$env:VCPKG_ROOT = $env:VCPKG_ROOT
$env:VCPKG_DEFAULT_TRIPLET = "x64-windows-static"
$env:RUSTFLAGS = "-C target-feature=+crt-static"
cargo build --release --target x86_64-pc-windows-msvc

# 9. Raccogli artefatti
Write-Host "Raccolgo artefatti..."
$exeSource = ".\target\x86_64-pc-windows-msvc\release\rustdesk.exe"
if (-not (Test-Path $exeSource)) {
  Write-Error "Eseguibile non trovato: $exeSource"
  exit 1
}

Remove-Item -Recurse -Force $OutputDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $OutputDir | Out-Null
Copy-Item $exeSource -Destination "$OutputDir\rustdesk-custom.exe" -Force
Copy-Item ".\src\ui\config.json" -Destination $OutputDir -Force

# 10. Genera package ZIP
Write-Host "Creo pacchetto ZIP..."
Push-Location $OutputDir
if (Test-Path ".\package.zip") { Remove-Item package.zip }
Compress-Archive -Path * -DestinationPath package.zip -Force
Pop-Location

Pop-Location

Write-Host "=== Build completata. Artefatti in $OutputDir ==="
