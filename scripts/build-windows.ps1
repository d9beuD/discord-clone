# Full Windows build: native Rust DLL, C# bindings, then the WinUI 3 app.
# Run from a PowerShell prompt on Windows (repository clone path, no macOS equivalent).
#   .\scripts\build-windows.ps1                 # Debug
#   .\scripts\build-windows.ps1 -Configuration Release -Publish
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",
    [switch]$Publish,
    [switch]$SkipBindings
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$CargoProfile = if ($Configuration -eq "Release") { "release" } else { "dev" }
$ProfileDir = if ($Configuration -eq "Release") { "release" } else { "debug" }
$Target = "x86_64-pc-windows-msvc"

rustup target add $Target | Out-Null

# cargo check cannot prove the link, so the cdylib is really built here.
cargo build --locked -p chat-bridge --lib --target $Target --profile $CargoProfile
if ($LASTEXITCODE -ne 0) { throw "cargo build failed for $Target" }

$Dll = Join-Path $Root "target/$Target/$ProfileDir/chat_bridge.dll"
if (-not (Test-Path $Dll)) { throw "Expected native library missing: $Dll" }

if (-not $SkipBindings) {
    # build-windows.sh discovers the DLL by host platform and writes apps/windows/Generated.
    $env:CONFIGURATION = $Configuration
    & bash "$Root/scripts/build-windows.sh"
    if ($LASTEXITCODE -ne 0) { throw "Binding generation failed" }
}

$Proj = Join-Path $Root "apps/windows/DiscordClone.Windows.csproj"
if ($Publish) {
    dotnet publish $Proj -c $Configuration -r win-x64 --self-contained false `
        -o (Join-Path $Root "apps/windows/bin/publish")
} else {
    dotnet build $Proj -c $Configuration -r win-x64
}
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed" }

# The DLL must sit beside the executable because the bindings P/Invoke "chat_bridge" by name.
# The output path is discovered rather than hardcoded so it survives TFM changes.
$AppOut = Get-ChildItem -Path (Join-Path $Root "apps/windows/bin") -Recurse -Filter "DiscordClone.Windows.exe" |
    Select-Object -First 1 -ExpandProperty DirectoryName
if (-not $AppOut) { throw "Could not locate the app output directory" }
Copy-Item $Dll $AppOut -Force
Write-Host "Native DLL installed next to the app: $AppOut"
Write-Host "Launch with: & (Join-Path '$AppOut' 'DiscordClone.Windows.exe')"
