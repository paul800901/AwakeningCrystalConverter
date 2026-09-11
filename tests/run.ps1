param([string]$Lua = 'build/lua-check-runtime/lua.exe')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    & (Join-Path $root 'tools/generate_localizations.ps1') -Check
    foreach($test in @('test-power-runtime.lua','test-construction.lua','test-technology-order.lua','check-target-ui-0.3.1.lua','test-localization.lua')) {
        & $Lua (Join-Path 'tests' $test)
        if($LASTEXITCODE -ne 0) { throw "Failed: $test" }
    }
} finally { Pop-Location }
