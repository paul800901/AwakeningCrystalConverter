[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$version=(Get-Content (Join-Path $root 'src/PalAwakeningExchangePrototype/metadata.json') -Raw | ConvertFrom-Json).version
if (!$OutputDirectory) { $OutputDirectory=Join-Path $root ('dist/public-'+$version+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')) }
$out=[IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $out) { throw 'Use a new output directory.' }
$dist=[IO.Path]::GetFullPath((Join-Path $root 'dist'))
if (!$out.StartsWith($dist+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Release output must be inside project dist.' }
$modules=[ordered]@{
    PalAwakeningExchangePrototype='Mods/PalSchema/mods/PalAwakeningExchangePrototype'
    AwakeningCrystalConverterUI='Mods/AwakeningCrystalConverterUI'
    AwakeningCrystalCoreProbe='Mods/AwakeningCrystalCoreProbe'
}
foreach($entry in $modules.GetEnumerator()) {
    $source=Join-Path $dist $entry.Key
    foreach($file in Get-ChildItem -LiteralPath $source -Recurse -File) {
        $relative=[IO.Path]::GetRelativePath($source,$file.FullName)
        $target=Join-Path (Join-Path $out $entry.Value) $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
        if ((Get-FileHash $target).Hash -ne (Get-FileHash $file.FullName).Hash) { throw "Package copy mismatch: $relative" }
    }
}
foreach($file in @('LICENSE','THIRD_PARTY_NOTICES.md','README.md')) { Copy-Item -LiteralPath (Join-Path $root $file) -Destination (Join-Path $out $file) }
foreach($file in @('DESCRIPTION.txt','CHANGELOG.txt')) { Copy-Item -LiteralPath (Join-Path $root "workshop/$file") -Destination (Join-Path $out $file) }
Copy-Item -LiteralPath (Join-Path $root 'workshop/media/flow-cover.jpg') -Destination (Join-Path $out 'thumbnail.jpg')
$info=[ordered]@{
    ModName=([IO.File]::ReadAllText((Join-Path $root 'workshop/TITLE.txt')).Trim());PackageName='AwakeningCrystalConverter';Thumbnail='thumbnail.jpg'
    Version=$version;DebugMode=$false;MinRevision=102642;Author='paul800901'
    Dependencies=@('UE4SSExperimentalPW','PalSchema');Tags=@('UE4SS','PalSchema','Gameplay')
    InstallRule=@(@{Type='UE4SS';Targets=@('./Mods')})
}
[IO.File]::WriteAllText((Join-Path $out 'Info.json'),($info|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
Compress-Archive -Path (Join-Path $out '*') -DestinationPath ($out+'.zip') -CompressionLevel Optimal
Write-Output "Package: $out"
Write-Output "Archive: $out.zip"
