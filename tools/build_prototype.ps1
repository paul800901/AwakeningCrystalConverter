param(
    [string]$EngineRoot = 'D:\幻獸帕魯模組\PalSkillDPSAnalyzer\.toolchain\UnrealEngine-5.1\Engine',
    [string]$SdkProject = 'D:\幻獸帕魯模組\PalResourceFactoryMod\unreal',
    [string]$SharedPluginRoot = 'D:\幻獸帕魯模組\PalSkillDPSAnalyzer\.toolchain\PalworldModdingKit\Plugins',
    [ValidateSet('Author', 'Cook', 'Package', 'All')][string]$Stage = 'All'
)
$ErrorActionPreference = 'Stop'
$prototypeRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $prototypeRoot 'build'
$editorRoot = Join-Path $buildRoot 'editor'
$uproject = Join-Path $editorRoot 'PalAwakeningExchange.uproject'
$editorExe = Join-Path $EngineRoot 'Binaries\Win64\UnrealEditor-Cmd.exe'
$pakExe = Join-Path $EngineRoot 'Binaries\Win64\UnrealPak.exe'
$moduleRoot = Join-Path $SdkProject 'Binaries\Win64'
$pluginRoot = $SharedPluginRoot
foreach ($path in @($editorExe, $pakExe, $moduleRoot, $pluginRoot)) {
    if (!(Test-Path -LiteralPath $path)) { throw "Missing existing toolchain input: $path" }
}

if ($Stage -in @('Author', 'All')) {
    foreach ($dir in @('Config', 'Binaries\Win64', 'Content', 'Plugins\Wwise\Binaries\Win64')) {
        New-Item -ItemType Directory -Path (Join-Path $editorRoot $dir) -Force | Out-Null
    }
    Get-ChildItem -LiteralPath $moduleRoot -File | Where-Object {
        $_.Extension -eq '.dll' -or $_.Name -eq 'UnrealEditor.modules'
    } | Copy-Item -Destination (Join-Path $editorRoot 'Binaries\Win64')
    Copy-Item -LiteralPath (Join-Path $SdkProject 'Plugins\Wwise\Wwise.uplugin') -Destination (Join-Path $editorRoot 'Plugins\Wwise')
    foreach ($name in @('UnrealEditor-AkAudio.dll', 'UnrealEditor.modules')) {
        Copy-Item -LiteralPath (Join-Path $SdkProject "Plugins\Wwise\Binaries\Win64\$name") -Destination (Join-Path $editorRoot 'Plugins\Wwise\Binaries\Win64')
    }
    $enabled = @('EditorScriptingUtilities', 'PythonScriptPlugin', 'CommonGame', 'CommonUser', 'Flow', 'ModularGameplay', 'ModularGameplayActors', 'PocketpairUser', 'PPSkyCreatorPlugin', 'DiscordPartnerSDK', 'DLSS', 'Wwise')
    $disabled = @('LiveLink', 'LiveLinkCamera', 'MayaLiveLink', 'InterchangeEditor', 'OnlineSubsystemEOS', 'EOSShared', 'EOSVoiceChat', 'SocketSubsystemEOS', 'OnlineSubsystemSteam')
    $plugins = @($enabled | ForEach-Object { @{Name=$_; Enabled=$true} }) + @($disabled | ForEach-Object { @{Name=$_; Enabled=$false} })
    @{
        FileVersion=3; EngineAssociation='5.1'; Category='Mods'; Description='Local awakening exchange feasibility prototype';
        AdditionalPluginDirectories=@($pluginRoot);
        Modules=@(@{Name='Pal'; Type='Runtime'; LoadingPhase='Default'}, @{Name='PalModLoader'; Type='Runtime'; LoadingPhase='PostConfigInit'});
        Plugins=$plugins; TargetPlatforms=@('Windows')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $uproject -Encoding utf8
    @'
[/Script/EngineSettings.GameMapsSettings]
EditorStartupMap=/Engine/Maps/Entry
GameDefaultMap=/Engine/Maps/Entry

[/Script/Engine.RendererSettings]
r.AllowStaticLighting=False
'@ | Set-Content -LiteralPath (Join-Path $editorRoot 'Config\DefaultEngine.ini') -Encoding utf8
    @'
[/Script/UnrealEd.ProjectPackagingSettings]
bUseIoStore=False
bShareMaterialShaderCode=False
bSharedMaterialNativeLibraries=False
+DirectoriesToAlwaysCook=(Path="/Game/PalAwakeningExchange")
+DirectoriesToNeverCook=(Path="/Game/PAE_EditorChecks")
'@ | Set-Content -LiteralPath (Join-Path $editorRoot 'Config\DefaultGame.ini') -Encoding utf8
    $authorLog = Join-Path $buildRoot 'author.log'
    & $editorExe $uproject '-run=pythonscript' "-script=$(Join-Path $prototypeRoot 'unreal\create_exchange_machine.py')" '-unattended' '-NullRHI' '-NoSound' '-NoSplash' '-NoCompile' '-NoHotReload' '-UTF8Output' "-abslog=$authorLog" *> (Join-Path $buildRoot 'author-console.txt')
    if ($LASTEXITCODE -ne 0) { throw "Unreal authoring failed ($LASTEXITCODE); see $authorLog" }
    if (!(Select-String -LiteralPath $authorLog -SimpleMatch '[PAE] EDITOR_CHECK_OK' -Quiet)) { throw "Missing Unreal editor check result; see $authorLog" }
    if (!(Select-String -LiteralPath $authorLog -SimpleMatch '[PAE] CONTAINMENT_EDITOR_CHECK_OK' -Quiet)) { throw "Missing containment editor result; see $authorLog" }
}

if ($Stage -in @('Cook', 'All')) {
    $cookLog = Join-Path $buildRoot 'cook.log'
    # Cook both explicitly in one run: a second non-iterative cook clears the first.
    # Skip references so editor-only stand-ins for game assets never enter the pak.
    $assetRoot = Join-Path $editorRoot 'Content\PalAwakeningExchange'
    $packages = @(Get-ChildItem -LiteralPath $assetRoot -Filter '*.uasset' -File -Recurse | ForEach-Object {
        '/Game/PalAwakeningExchange/' + $_.FullName.Substring($assetRoot.Length).TrimStart('\').Replace('\', '/').Replace('.uasset', '')
    })
    & $editorExe $uproject '-run=cook' '-targetplatform=Windows' '-cooksinglepackagenorefs' ("-PACKAGE=" + ($packages -join '+')) '-unattended' '-NullRHI' '-noshaderworker' '-NoSound' '-NoSplash' '-NoCompile' '-NoHotReload' '-UTF8Output' "-abslog=$cookLog" *> (Join-Path $buildRoot 'cook-console.txt')
    if ($LASTEXITCODE -ne 0) { throw "Unreal cook failed ($LASTEXITCODE); see $cookLog" }
    foreach ($asset in @('BP_PAE_ExchangePrototype', 'BP_PAE_ContainmentProbe')) {
        if (!(Test-Path -LiteralPath (Join-Path $editorRoot "Saved\Cooked\Windows\PalAwakeningExchange\Content\PalAwakeningExchange\$asset.uexp"))) {
            throw "Cook produced no $asset asset; see $cookLog"
        }
    }
}

if ($Stage -in @('Package', 'All')) {
    $cookedRoot = Join-Path $editorRoot 'Saved\Cooked\Windows\PalAwakeningExchange\Content\PalAwakeningExchange'
    $cookedFiles = @(Get-ChildItem -LiteralPath $cookedRoot -File -Recurse | Where-Object { $_.Extension -in @('.uasset', '.uexp', '.ubulk') })
    foreach ($asset in @('BP_PAE_ExchangePrototype', 'BP_PAE_ContainmentProbe')) {
        foreach ($extension in @('.uasset', '.uexp')) {
            if (!(Test-Path -LiteralPath (Join-Path $cookedRoot ($asset + $extension)))) {
                throw "Missing cooked asset: $asset$extension"
            }
        }
    }
    $distRoot = Join-Path $prototypeRoot 'dist'
    $modRoot = Join-Path $distRoot 'PalAwakeningExchangePrototype'
    New-Item -ItemType Directory -Path (Join-Path $modRoot 'paks') -Force | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $prototypeRoot 'src\PalAwakeningExchangePrototype') | Copy-Item -Destination $modRoot -Recurse -Force
    # The source selector runs in the already installed UE4SS Lua runtime.
    # Keep it beside the PalSchema data mod, for its separate Mods directory.
    Copy-Item -LiteralPath (Join-Path $prototypeRoot 'src\AwakeningCrystalConverterUI') -Destination $distRoot -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $prototypeRoot 'src\AwakeningCrystalCoreProbe') -Destination $distRoot -Recurse -Force
    $lines = @($cookedFiles | ForEach-Object {
        $relative = $_.FullName.Substring($cookedRoot.Length).TrimStart('\').Replace('\', '/')
        '"' + $_.FullName + '" "../../../Pal/Content/PalAwakeningExchange/' + $relative + '"'
    })
    $responseFile = Join-Path $buildRoot 'pak-response.txt'
    $lines | Set-Content -LiteralPath $responseFile -Encoding utf8
    $pakPath = Join-Path $modRoot 'paks\PalAwakeningExchange_P.pak'
    & $pakExe $pakPath "-create=$responseFile" '-compress' '-unattended' "-abslog=$(Join-Path $buildRoot 'pak-create.log')" *> (Join-Path $buildRoot 'pak-create-console.txt')
    if ($LASTEXITCODE -ne 0) { throw 'UnrealPak creation failed' }
    & $pakExe $pakPath '-List' '-unattended' "-abslog=$(Join-Path $buildRoot 'pak-list.log')" *> (Join-Path $buildRoot 'pak-list-console.txt')
    if ($LASTEXITCODE -ne 0) { throw 'UnrealPak list failed' }
    Write-Output "Local package: $modRoot"
}
