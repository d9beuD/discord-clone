#!/usr/bin/env python3
"""Regenerate the checked-in Xcode project without third-party dependencies."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent.parent
MACOS = ROOT / "apps/macos"
PROJECT = MACOS / "DiscordClone.xcodeproj"
PROJECT.mkdir(exist_ok=True)
objects = {}


def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def quote(value):
    return json.dumps(value, ensure_ascii=False)


def value(item):
    if isinstance(item, dict):
        return "{ " + " ".join(f"{key} = {value(val)};" for key, val in item.items()) + " }"
    if isinstance(item, list):
        return "(" + ", ".join(value(val) for val in item) + ",)" if item else "()"
    return quote(str(item))


def add(key, isa, **fields):
    uid = ident(key)
    objects[uid] = {"isa": isa, **fields}
    return uid


project_id = ident("project")
app_id = ident("DiscordClone")
products = []
groups = []
targets = []
target_settings = {
    "DiscordClone": {
        "PRODUCT_BUNDLE_IDENTIFIER": "dev.discordclone.macos",
        "INFOPLIST_KEY_CFBundleDisplayName": "Discord Clone",
        "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.social-networking",
        "INFOPLIST_KEY_NSPrincipalClass": "NSApplication",
        "LIBRARY_SEARCH_PATHS": ["$(inherited)", "$(SRCROOT)/Generated/$(CONFIGURATION)"],
        "SWIFT_INCLUDE_PATHS": "$(SRCROOT)/Generated/$(CONFIGURATION)",
        "OTHER_SWIFT_FLAGS": ["$(inherited)", "-Xcc", "-fmodule-map-file=$(SRCROOT)/Generated/$(CONFIGURATION)/ChatBridgeFFI.modulemap"],
        "OTHER_LDFLAGS": ["$(inherited)", "-lapple_bridge", "-liconv"],
    },
    "DiscordCloneTests": {
        "PRODUCT_BUNDLE_IDENTIFIER": "dev.discordclone.macos.tests",
        "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/DiscordClone.app/Contents/MacOS/DiscordClone",
        "BUNDLE_LOADER": "$(TEST_HOST)",
        "SWIFT_INCLUDE_PATHS": "$(SRCROOT)/Generated/$(CONFIGURATION)",
        "OTHER_SWIFT_FLAGS": ["$(inherited)", "-Xcc", "-fmodule-map-file=$(SRCROOT)/Generated/$(CONFIGURATION)/ChatBridgeFFI.modulemap"],
    },
    "DiscordCloneUITests": {
        "PRODUCT_BUNDLE_IDENTIFIER": "dev.discordclone.macos.uitests",
        "TEST_TARGET_NAME": "DiscordClone",
    },
}

for name, folders, product_type in [
    ("DiscordClone", ["App", "Features", "Components", "ViewModels"], "application"),
    ("DiscordCloneTests", ["Tests"], "bundle.unit-test"),
    ("DiscordCloneUITests", ["UITests"], "bundle.ui-testing"),
]:
    refs, builds = [], []
    files = sorted(path for folder in folders for path in (MACOS / folder).rglob("*.swift"))
    source_paths = [str(path.relative_to(MACOS)) for path in files]
    if name == "DiscordClone":
        source_paths.append("Generated/$(CONFIGURATION)/ChatBridge.swift")
    for path in source_paths:
        ref = add("file:" + path, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=path, sourceTree="SOURCE_ROOT")
        refs.append(ref)
        builds.append(add(name + ":build:" + path, "PBXBuildFile", fileRef=ref))
    groups.append(add(name + ":group", "PBXGroup", name=name, children=refs, sourceTree="<group>"))
    extension = "app" if product_type == "application" else "xctest"
    product = add(name + ":product", "PBXFileReference", explicitFileType="wrapper.application" if extension == "app" else "wrapper.cfbundle", path=name + "." + extension, sourceTree="BUILT_PRODUCTS_DIR")
    products.append(product)
    phases = []
    if name == "DiscordClone":
        inputs = ["$(SRCROOT)/../../Cargo.toml", "$(SRCROOT)/../../Cargo.lock", "$(SRCROOT)/../../scripts/build-rust.sh"]
        inputs += ["$(SRCROOT)/../../" + str(path.relative_to(ROOT)) for path in sorted((ROOT / "crates").rglob("*")) if path.suffix in [".rs", ".toml"]]
        outputs = ["$(SRCROOT)/Generated/$(CONFIGURATION)/" + path for path in ["ChatBridge.swift", "ChatBridgeFFI.h", "ChatBridgeFFI.modulemap", "libapple_bridge.a"]]
        phases.append(add("rust:phase", "PBXShellScriptBuildPhase", buildActionMask=2147483647, files=[], inputPaths=inputs, outputPaths=outputs, name="Build Rust and generate UniFFI", shellPath="/bin/bash", shellScript='"$SRCROOT/../../scripts/build-rust.sh"\n', runOnlyForDeploymentPostprocessing=0, alwaysOutOfDate=1))
    phases.append(add(name + ":sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0))
    phases.append(add(name + ":frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0))
    configs = []
    for config in ["Debug", "Release"]:
        settings = {
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "GENERATE_INFOPLIST_FILE": "YES",
            "CODE_SIGN_STYLE": "Manual",
            "CODE_SIGN_IDENTITY": "-",
            "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks"],
            **target_settings[name],
        }
        configs.append(add(name + ":" + config, "XCBuildConfiguration", name=config, buildSettings=settings))
    config_list = add(name + ":configs", "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
    dependencies = []
    if name != "DiscordClone":
        proxy = add(name + ":proxy", "PBXContainerItemProxy", containerPortal=project_id, proxyType=1, remoteGlobalIDString=app_id, remoteInfo="DiscordClone")
        dependencies.append(add(name + ":dependency", "PBXTargetDependency", target=app_id, targetProxy=proxy))
    targets.append(add(name, "PBXNativeTarget", name=name, productName=name, buildConfigurationList=config_list, buildPhases=phases, buildRules=[], dependencies=dependencies, productReference=product, productType="com.apple.product-type." + product_type))

products_group = add("products", "PBXGroup", name="Products", children=products, sourceTree="<group>")
main_group = add("main", "PBXGroup", children=groups + [products_group], sourceTree="<group>")
configs = []
for config in ["Debug", "Release"]:
    settings = {
        "SDKROOT": "macosx",
        "MACOSX_DEPLOYMENT_TARGET": "27.0",
        "ARCHS": "arm64",
        "SWIFT_VERSION": "6.0",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "ENABLE_TESTABILITY": "YES" if config == "Debug" else "NO",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if config == "Debug" else "dwarf-with-dsym",
    }
    configs.append(add("project:" + config, "XCBuildConfiguration", name=config, buildSettings=settings))
config_list = add("project:configs", "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
add("project", "PBXProject", attributes={"LastUpgradeCheck": "2700", "BuildIndependentTargetsInParallel": "YES"}, buildConfigurationList=config_list, compatibilityVersion="Xcode 14.0", developmentRegion="fr", knownRegions=["fr", "en", "Base"], mainGroup=main_group, productRefGroup=products_group, projectDirPath="", projectRoot="", targets=targets)

body = "// !$*UTF8*$!\n{\n archiveVersion = 1;\n classes = {};\n objectVersion = 56;\n objects = {\n"
body += "\n".join(f"  {uid} = {value(fields)};" for uid, fields in objects.items())
body += f"\n }};\n rootObject = {project_id};\n}}\n"
(PROJECT / "project.pbxproj").write_text(body)

scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)


def reference(name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(name)}" BuildableName="{name}.{"app" if name == "DiscordClone" else "xctest"}" BlueprintName="{name}" ReferencedContainer="container:DiscordClone.xcodeproj"/>'


scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference("DiscordClone")}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
    <TestableReference skipped="NO">{reference("DiscordCloneTests")}</TestableReference>
    <TestableReference skipped="NO">{reference("DiscordCloneUITests")}</TestableReference>
  </Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference("DiscordClone")}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference("DiscordClone")}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(scheme_dir / "DiscordClone.xcscheme").write_text(scheme)
print("Xcode project generated")
