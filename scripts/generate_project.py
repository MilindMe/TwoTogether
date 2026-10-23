"""Generate a dependency-free Xcode project; safe to rerun after source changes."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parents[1]
ios = root / 'ios'
project = ios / 'TwoTogether.xcodeproj'
project.mkdir(exist_ok=True)
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def ref(name): return uid(name)
objects = []
def add(name, value): objects.append(f'{uid(name)} = {{ {value} }};')
files = sorted((ios / 'TwoTogether').glob('*.swift'))
source_ids = []
file_ids = []
for file in files + [root / 'Sources/HabitCore/Models.swift']:
    path = str(file.relative_to(ios)) if file.is_relative_to(ios) else '../Sources/HabitCore/Models.swift'
    add(path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = SOURCE_ROOT;')
    add(path + '-build', f'isa = PBXBuildFile; fileRef = {uid(path)};')
    file_ids.append(uid(path)); source_ids.append(uid(path + '-build'))
add('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = TwoTogether/Assets.xcassets; sourceTree = SOURCE_ROOT;')
add('assets-build', f'isa = PBXBuildFile; fileRef = {uid("assets")};')
add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = TwoTogether.app; sourceTree = BUILT_PRODUCTS_DIR;')
add('rootgroup', f'isa = PBXGroup; children = ({",".join(file_ids)},{uid("assets")},{uid("products")},); sourceTree = "<group>";')
add('products', f'isa = PBXGroup; children = ({uid("product")},); name = Products; sourceTree = "<group>";')
add('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(source_ids)},); runOnlyForDeploymentPostprocessing = 0;')
add('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({uid("assets-build")},); runOnlyForDeploymentPostprocessing = 0;')
add('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
base = 'SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES;'
app = 'PRODUCT_BUNDLE_IDENTIFIER = com.twotogether.habits; PRODUCT_NAME = "$(TARGET_NAME)"; INFOPLIST_FILE = TwoTogether/Info.plist; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0; TARGETED_DEVICE_FAMILY = "1,2"; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; SWIFT_EMIT_LOC_STRINGS = YES;'
for kind in ['project', 'app']:
    for mode in ['Debug', 'Release']:
        settings = base + (app if kind == 'app' else '') + (' CODE_SIGN_ENTITLEMENTS = TwoTogether/TwoTogetherLocal.entitlements;' if kind == 'app' and mode == 'Debug' else ' CODE_SIGN_ENTITLEMENTS = TwoTogether/TwoTogether.entitlements;' if kind == 'app' else '') + (' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if mode == 'Debug' else ' SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";') + (' SWIFT_ACTIVE_COMPILATION_CONDITIONS = PUSH_NOTIFICATIONS;' if kind == 'app' and mode == 'Release' else '')
        add(kind + mode, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {mode};')
    add(kind + 'configs', f'isa = XCConfigurationList; buildConfigurations = ({uid(kind+"Debug")},{uid(kind+"Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("appconfigs")}; buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resources")},); buildRules = (); dependencies = (); name = TwoTogether; productName = TwoTogether; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; TargetAttributes = {{ {uid("target")} = {{ CreatedOnToolsVersion = 27.1; }}; }}; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = {uid("rootgroup")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")},);')
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {uid("project")}; }}\n')
scheme = project / 'xcshareddata/xcschemes/TwoTogether.xcscheme'
scheme.parent.mkdir(parents=True, exist_ok=True)
entry = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target")}" BuildableName="TwoTogether.app" BlueprintName="TwoTogether" ReferencedContainer="container:TwoTogether.xcodeproj"/>'
scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{entry}</BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{entry}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{entry}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print(project)
