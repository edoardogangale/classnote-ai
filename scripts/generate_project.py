#!/usr/bin/env python3
"""Generate both real Xcode projects using only Python's standard library. No XcodeGen needed."""
import hashlib
import json
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parents[1]

def uid(text):
    return hashlib.sha1(text.encode()).hexdigest()[:24].upper()

def quote(text):
    return json.dumps(str(text), ensure_ascii=False)

def build(with_whisper=False):
    name = 'ClassNoteAIWhisper' if with_whisper else 'ClassNoteAI'
    project = ROOT / f'{name}.xcodeproj'
    shared = project / 'xcshareddata/xcschemes'
    shared.mkdir(parents=True, exist_ok=True)
    objects = []
    def obj(key, body):
        identifier = uid(key)
        objects.append(f'\t\t{identifier} = {{ {body} }};')
        return identifier
    def arr(values):
        return '(' + ', '.join(values) + (',' if values else '') + ')'
    app_id, test_id = uid('app'), uid('test')
    source_refs, source_build = [], []
    for folder in ('App','Audio','Transcription','Storage','Notebook','Documents','Study','Views'):
        for path in sorted((ROOT/folder).glob('*.swift')):
            rel = path.relative_to(ROOT).as_posix()
            ref = obj('file:'+rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(rel)}; sourceTree = "<group>";')
            source_refs.append(ref)
            source_build.append(obj('build:'+rel,f'isa = PBXBuildFile; fileRef = {ref};'))
    test_refs, test_build = [], []
    for path in sorted((ROOT/'Tests').glob('*.swift')):
        rel = path.relative_to(ROOT).as_posix()
        ref = obj('file:'+rel,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(rel)}; sourceTree = "<group>";')
        test_refs.append(ref)
        test_build.append(obj('build:'+rel,f'isa = PBXBuildFile; fileRef = {ref};'))
    resource_refs, resource_build = [], []
    for path, kind in [('Resources/Assets.xcassets','folder.assetcatalog'),('Resources/Math','folder'),('Resources/PrivacyInfo.xcprivacy','text.xml')]:
        ref = obj('file:'+path,f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(path)}; sourceTree = "<group>";')
        resource_refs.append(ref)
        resource_build.append(obj('build:'+path,f'isa = PBXBuildFile; fileRef = {ref};'))
    plist = obj('file:Info', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Resources/Info.plist; sourceTree = "<group>";')
    sqlite = obj('sqlite','isa = PBXFileReference; lastKnownFileType = sourcecode.text-based-dylib-definition; name = libsqlite3.tbd; path = usr/lib/libsqlite3.tbd; sourceTree = SDKROOT;')
    sqlitebuild = obj('sqlitebuild',f'isa = PBXBuildFile; fileRef = {sqlite};')
    app = obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ClassNoteAI.app; sourceTree = BUILT_PRODUCTS_DIR;')
    test = obj('testproduct','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ClassNoteAITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    core = obj('corepackage','isa = XCLocalSwiftPackageReference; relativePath = Packages/ClassNoteCore;')
    coreproduct = obj('coreproduct',f'isa = XCSwiftPackageProductDependency; package = {core}; productName = ClassNoteCore;')
    coretestproduct = obj('coretestproduct',f'isa = XCSwiftPackageProductDependency; package = {core}; productName = ClassNoteCore;')
    corebuild = obj('corebuild',f'isa = PBXBuildFile; productRef = {coreproduct};')
    coretestbuild = obj('coretestbuild',f'isa = PBXBuildFile; productRef = {coretestproduct};')
    packages, products, links = [core], [coreproduct], [corebuild,sqlitebuild]
    if with_whisper:
        package = obj('whisperpackage','isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/argmaxinc/WhisperKit.git"; requirement = {kind = exactVersion; version = 0.9.0;};')
        product = obj('whisperproduct',f'isa = XCSwiftPackageProductDependency; package = {package}; productName = WhisperKit;')
        packages.append(package); products.append(product)
        links.append(obj('whisperbuild',f'isa = PBXBuildFile; productRef = {product};'))
    sources = obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(source_build)}; runOnlyForDeploymentPostprocessing = 0;')
    resources = obj('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {arr(resource_build)}; runOnlyForDeploymentPostprocessing = 0;')
    frameworks = obj('frameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {arr(links)}; runOnlyForDeploymentPostprocessing = 0;')
    testsources = obj('testsources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(test_build)}; runOnlyForDeploymentPostprocessing = 0;')
    testframeworks = obj('testframeworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {arr([coretestbuild])}; runOnlyForDeploymentPostprocessing = 0;')
    testresources = obj('testresources','isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    proxy = obj('proxy',f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {app_id}; remoteInfo = ClassNoteAI;')
    dependency = obj('dependency',f'isa = PBXTargetDependency; target = {app_id}; targetProxy = {proxy};')
    project_configs, app_configs, test_configs = [], [], []
    for mode in ('Debug','Release'):
        common = {
            'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES',
            'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0',
            'SWIFT_STRICT_CONCURRENCY':'targeted','ENABLE_TESTABILITY':'YES' if mode == 'Debug' else 'NO',
            'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode == 'Debug' else '-O',
            'DEBUG_INFORMATION_FORMAT':'dwarf' if mode == 'Debug' else 'dwarf-with-dsym',
            'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG $(inherited)' if mode == 'Debug' else '$(inherited)',
        }
        appsettings = {
            'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','CODE_SIGN_STYLE':'Automatic',
            'CURRENT_PROJECT_VERSION':'5','MARKETING_VERSION':'0.3.0','GENERATE_INFOPLIST_FILE':'NO',
            'INFOPLIST_FILE':'Resources/Info.plist','PRODUCT_BUNDLE_IDENTIFIER':'it.lorenzo.classnote',
            'PRODUCT_NAME':'ClassNoteAI','PRODUCT_MODULE_NAME':'ClassNoteAI','TARGETED_DEVICE_FAMILY':'2',
            'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO',
            'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks',
            'ENABLE_PREVIEWS':'YES',
        }
        testsettings = {
            'CODE_SIGN_STYLE':'Automatic','GENERATE_INFOPLIST_FILE':'YES',
            'PRODUCT_BUNDLE_IDENTIFIER':'it.lorenzo.classnote.tests','PRODUCT_NAME':'ClassNoteAITests',
            'TARGETED_DEVICE_FAMILY':'2','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/ClassNoteAI.app/ClassNoteAI',
            'BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @loader_path/Frameworks',
        }
        for kind,settings,target in [('p',common,project_configs),('a',appsettings,app_configs),('t',testsettings,test_configs)]:
            body = ' '.join(f'{key} = {quote(value)};' for key,value in settings.items())
            target.append(obj('config:'+kind+mode,f'isa = XCBuildConfiguration; buildSettings = {{{body}}}; name = {mode};'))
    def configlist(key,configs):
        return obj(key,f'isa = XCConfigurationList; buildConfigurations = {arr(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    pc, ac, tc = configlist('pc',project_configs), configlist('ac',app_configs), configlist('tc',test_configs)
    obj('app',f'isa = PBXNativeTarget; buildConfigurationList = {ac}; buildPhases = {arr([sources,frameworks,resources])}; buildRules = (); dependencies = (); name = {name}; packageProductDependencies = {arr(products)}; productName = ClassNoteAI; productReference = {app}; productType = "com.apple.product-type.application";')
    obj('test',f'isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = {arr([testsources,testframeworks,testresources])}; buildRules = (); dependencies = {arr([dependency])}; name = ClassNoteAITests; packageProductDependencies = {arr([coretestproduct])}; productName = ClassNoteAITests; productReference = {test}; productType = "com.apple.product-type.bundle.unit-test";')
    sg = obj('sourcegroup',f'isa = PBXGroup; children = {arr(source_refs)}; name = Sources; sourceTree = "<group>";')
    tg = obj('testgroup',f'isa = PBXGroup; children = {arr(test_refs)}; name = Tests; sourceTree = "<group>";')
    rg = obj('resourcegroup',f'isa = PBXGroup; children = {arr(resource_refs+[plist])}; name = Resources; sourceTree = "<group>";')
    pg = obj('productgroup',f'isa = PBXGroup; children = {arr([app,test])}; name = Products; sourceTree = "<group>";')
    main = obj('main',f'isa = PBXGroup; children = {arr([sg,tg,rg,sqlite,pg])}; sourceTree = "<group>";')
    project_id = obj('project',f'isa = PBXProject; attributes = {{LastUpgradeCheck = 1600; TargetAttributes = {{{app_id} = {{CreatedOnToolsVersion = 16.0;}}; {test_id} = {{CreatedOnToolsVersion = 16.0; TestTargetID = {app_id};}};}};}}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = it; hasScannedForEncodings = 0; knownRegions = (it,en,Base); mainGroup = {main}; packageReferences = {arr(packages)}; productRefGroup = {pg}; projectDirPath = ""; projectRoot = ""; targets = {arr([app_id,test_id])};')
    text = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + '\n\t};\n\trootObject = ' + project_id + ';\n}\n'
    (project/'project.pbxproj').write_text(text)
    (project/'project.xcworkspace').mkdir(exist_ok=True)
    (project/'project.xcworkspace/contents.xcworkspacedata').write_text('<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n')
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_id}" BuildableName="ClassNoteAI.app" BlueprintName="{name}" ReferencedContainer="container:{name}.xcodeproj"/></BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_id}" BuildableName="ClassNoteAITests.xctest" BlueprintName="ClassNoteAITests" ReferencedContainer="container:{name}.xcodeproj"/></TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_id}" BuildableName="ClassNoteAI.app" BlueprintName="{name}" ReferencedContainer="container:{name}.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_id}" BuildableName="ClassNoteAI.app" BlueprintName="{name}" ReferencedContainer="container:{name}.xcodeproj"/></BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
    (shared/f'{name}.xcscheme').write_text(scheme)
    return project

if __name__ == '__main__':
    for whisper in (False,True):
        print(build(whisper).name)
