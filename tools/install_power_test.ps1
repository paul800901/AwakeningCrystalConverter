param([string]$GameRoot = 'E:\Program Files (x86)\Steam\steamapps\common\Palworld')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
if (Get-Process -Name 'Palworld-Win64-Shipping','Palworld-WinGDK-Shipping','Palworld' -ErrorAction SilentlyContinue) {
    throw 'Close Palworld before installing this test package.'
}
$mainPak=Join-Path $GameRoot 'Pal\Content\Paks\Pal-Windows.pak'
if ((Get-Item -LiteralPath $mainPak).Length -ne 43649125878) {
    throw 'Original game resource has not been restored to its expected size. Installation stopped.'
}
$steamApps=Split-Path -Parent (Split-Path -Parent $GameRoot)
$manifest=Get-Content -LiteralPath (Join-Path $steamApps 'appmanifest_1623730.acf') -Raw
if ($manifest -notmatch '"StateFlags"\s+"4"' -or $manifest -notmatch '"buildid"\s+"25094871"') {
    throw 'Steam must finish recovery of the original build before installation.'
}
$ue4ss=Join-Path $GameRoot 'Mods\NativeMods\UE4SS'
$destinations=[ordered]@{
    PalAwakeningExchangePrototype=(Join-Path $ue4ss 'Mods\PalSchema\mods\PalAwakeningExchangePrototype')
    AwakeningCrystalConverterUI=(Join-Path $ue4ss 'Mods\AwakeningCrystalConverterUI')
    AwakeningCrystalCoreProbe=(Join-Path $ue4ss 'Mods\AwakeningCrystalCoreProbe')
}
$backup=Join-Path $projectRoot ('build\installed-before-0.6.0-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
foreach($entry in $destinations.GetEnumerator()) {
    $source=Join-Path $projectRoot ('dist\'+$entry.Key)
    if (!(Test-Path -LiteralPath $source)) { throw "Missing package: $source" }
    if (Test-Path -LiteralPath $entry.Value) { Copy-Item -LiteralPath $entry.Value -Destination $backup -Recurse }
}
if (Test-Path -LiteralPath (Join-Path $ue4ss 'UE4SS.log')) {
    Copy-Item -LiteralPath (Join-Path $ue4ss 'UE4SS.log') -Destination (Join-Path $backup 'UE4SS-before.log')
}
$verified=@()
foreach($entry in $destinations.GetEnumerator()) {
    $source=Join-Path $projectRoot ('dist\'+$entry.Key)
    foreach($file in Get-ChildItem -LiteralPath $source -File -Recurse) {
        $relative=$file.FullName.Substring($source.Length).TrimStart('\')
        $target=Join-Path $entry.Value $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        $expected=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $actual=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if($expected -ne $actual) { throw "Installation readback mismatch: $target" }
        $verified+=@{Module=$entry.Key;File=$relative;EqualToPackage=$true;SHA256=$actual}
    }
}
@{Version='0.6.0';InstalledAt=(Get-Date).ToString('o');Backup=$backup;VerifiedFiles=$verified;GameRuntimeTested=$false} |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $projectRoot 'build\installed-0.6.0.json') -Encoding utf8
Write-Output "Installed 0.6.0; $($verified.Count) files read back; backup $backup"
