"""Source-built Android ARMv8-A libraries with per-binary provenance and ABI gates."""
from __future__ import annotations
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import shlex
import subprocess
import tarfile
import tempfile
import zipfile
from common import ROOT,WORK,download,run,sha256

FLAGS=['-O3','-DNDEBUG','-march=armv8-a','-flto=thin','-ffunction-sections','-fdata-sections','-fno-fast-math',
       '-fstack-protector-strong','-D_FORTIFY_SOURCE=2']
LINK=['-flto=thin','-Wl,--lto-O3','-Wl,--gc-sections','-Wl,-z,max-page-size=16384','-Wl,--build-id=sha1',
      '-Wl,-z,relro','-Wl,-z,now','-Wl,-z,noexecstack']
NATIVE=WORK/'native'
POLICY=ROOT/'.avx1/native-arm64.json'

def policy():return json.loads(POLICY.read_text('utf-8'))

def package_folder(name):
    from urllib.parse import urljoin,urlparse,unquote
    config=ROOT/'.dart_tool/package_config.json'
    entry=next(x for x in json.loads(config.read_text('utf-8'))['packages'] if x['name']==name)
    return Path(unquote(urlparse(urljoin(config.resolve().as_uri(),entry['rootUri'])).path))

def vendor_notices():
    pins=policy();target=ROOT/'android/app/src/main/assets/avx1-native-notices';target.mkdir(parents=True,exist_ok=True)
    vad=pins['bundled_vad']
    if sha256(ROOT/vad['bundled_path'])!=vad['model_sha256']:
        raise RuntimeError('Bundled upstream VAD detector changed; review model provenance')
    license_file=ROOT/'.avx1/licenses/Silero-VAD-MIT.txt'
    if sha256(license_file)!=vad['license_sha256']:raise RuntimeError('Silero VAD MIT notice differs')
    shutil.copy2(license_file,target/'Silero-VAD-MIT.txt')
    for package,version in (('jni',pins['jni']['version']),('sqlite3',pins['sqlite']['package_version'])):
        text=(package_folder(package)/'pubspec.yaml').read_text('utf-8')
        actual=re.search(r'(?m)^version:\s*[\'\"]?([^\s\'\"]+)',text)
        if not actual or actual.group(1)!=version:raise RuntimeError('Native Dart binding version changed: '+package)
    gradle=(package_folder('flutter_webrtc')/'android/build.gradle').read_text('utf-8')
    if 'io.github.webrtc-sdk:android:'+pins['webrtc_vendor']['version'] not in gradle:
        raise RuntimeError('WebRTC vendor version changed; review native provenance')
    pdfium=(package_folder('pdfium_dart')/'hook/build.dart').read_text('utf-8')
    if pins['pdfium_vendor']['encoded_release'] not in pdfium:raise RuntimeError('PDFium vendor revision changed')
    for item in pins['webrtc_vendor']['licenses']:
        path=target/('WebRTC-'+item['name']);download(item['url'],path,item['sha256'])
    pin=pins['pdfium_vendor'];archive=NATIVE/'pdfium-notices.tgz'
    if not archive.exists():download(pin['url'],archive,pin['sha256'])
    if sha256(archive)!=pin['sha256']:raise RuntimeError('PDFium vendor source archive hash changed')
    count=0
    with tarfile.open(archive) as stream:
        for member in stream:
            if member.isfile() and any(x in member.name.lower() for x in ('license','notice')):
                name='PDFium-'+re.sub('[^A-Za-z0-9._-]','_',member.name)
                (target/name).write_bytes(stream.extractfile(member).read());count+=1
    if count<2:raise RuntimeError('PDFium third-party license bundle is missing')
    (target/'AndroidX-DataStore-NOTICE.txt').write_text(
        'AndroidX DataStore '+pins['datastore_version']+'\nThe Android Open Source Project\nApache License 2.0; full text in dartjni-android-Apache-2.0.txt.\nSource: https://android.googlesource.com/platform/frameworks/support/\n',encoding='utf-8')

def extract_tar(archive,target):
    target.mkdir(parents=True,exist_ok=True)
    with tarfile.open(archive) as stream:stream.extractall(target,filter='data')

def pub_source(pin):
    target=NATIVE/'sources'/f"{pin['package']}-{pin['version']}"
    archive=target.with_name(target.name+'.tar.gz')
    if not archive.exists():download(pin['url'],archive,pin['sha256'])
    if sha256(archive)!=pin['sha256']:raise RuntimeError('Native pub source hash mismatch')
    if not target.exists():extract_tar(archive,target)
    return target

def toolchain():
    pins=json.loads((ROOT/'.avx1/toolchains.json').read_text('utf-8'))
    sdk=Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ['ANDROID_HOME'])
    ndk=sdk/'ndk'/pins['android']['ndk'].split(';')[1]
    tools=ndk/'toolchains/llvm/prebuilt/linux-x86_64/bin'
    clang=tools/'aarch64-linux-android24-clang'
    if not clang.is_file():raise RuntimeError('Pinned ARM64 NDK compiler is missing')
    return sdk,ndk,tools,clang

def symbols(binary,tools):
    result=run(tools/'llvm-nm','--dynamic','--defined-only',binary,capture=True).stdout
    return {line.split()[-1].split('@')[0] for line in result.splitlines() if line.split()}

def verify_elf(binary,tools):
    header=run(tools/'llvm-readelf','-h',binary,capture=True).stdout
    if 'AArch64' not in header:raise RuntimeError('Native binary is not AArch64: '+binary.name)
    segments=run(tools/'llvm-readelf','-lW',binary,capture=True).stdout
    loads=[line.split() for line in segments.splitlines() if line.lstrip().startswith('LOAD ')]
    if not loads or any(int(line[-1],16)<16384 for line in loads):
        raise RuntimeError('Native binary lacks Android 16 KiB page alignment: '+binary.name)

def build_id(binary,tools):
    notes=run(tools/'llvm-readelf','-n',binary,capture=True).stdout
    match=re.search(r'Build ID:\s*([a-f0-9]+)',notes)
    if not match:raise RuntimeError('Rebuilt native binary lacks a build ID')
    return match.group(1)

def flutter_reference(tools):
    pin=policy()['flutter_engine']
    framework=json.loads((ROOT/'.avx1/toolchains.json').read_text('utf-8'))
    engine=(WORK/'flutter/bin/internal/engine.version').read_text('utf-8').strip()
    if framework['flutter_sha']!=pin['framework_commit'] or engine!=pin['engine_commit']:
        raise RuntimeError('Flutter engine changed; review the official native artifact')
    archive=NATIVE/'flutter-engine.zip'
    if not archive.exists():download(pin['url'],archive,pin['sha256'])
    if sha256(archive)!=pin['sha256']:raise RuntimeError('Official Flutter engine archive hash mismatch')
    with zipfile.ZipFile(archive) as outer,zipfile.ZipFile(io.BytesIO(outer.read('flutter.jar'))) as jar:
        data=jar.read('lib/arm64-v8a/libflutter.so')
    if hashlib.sha256(data).hexdigest()!=pin['unstripped_sha256']:
        raise RuntimeError('Official Flutter engine binary hash mismatch')
    target=NATIVE/'official-libflutter.so';target.write_bytes(data)
    run(tools/'llvm-strip','--strip-unneeded',target)
    return {'engine_commit':engine,'official_artifact':pin['url'],'official_artifact_sha256':pin['sha256'],
            'official_unstripped_sha256':pin['unstripped_sha256'],'expected_packaged_sha256':sha256(target),
            'build_id':build_id(target,tools)}

def onnx_compile_evidence(build):
    path=build/'Release/compile_commands.json'
    entries=json.loads(path.read_text('utf-8'))
    core=[e for e in entries if '/onnxruntime/core/' in str(e['file']).replace('\\','/')]
    cxx=[e for e in core if Path(e['file']).suffix.lower() in ('.c','.cc','.cpp','.cxx')]
    jni=[e for e in entries if '/java/src/main/native/' in str(e['file']).replace('\\','/')]
    selected=cxx+jni
    if not cxx or not jni:raise RuntimeError('ONNX core/JNI compiler command evidence is missing')
    commands=[e.get('arguments') or shlex.split(e['command']) for e in selected]
    for args in commands:
        optimizations=[a for a in args if re.fullmatch('-O[0123szgfast]+',a)]
        lto=[a for a in args if a.startswith('-flto') or a=='-fno-lto']
        if not optimizations or optimizations[-1]!='-O3' or not lto or lto[-1]!='-flto=thin':
            raise RuntimeError('Effective ONNX core compilation differs from O3 ThinLTO')
        if '-ffast-math' in args or '-mcpu=native' in args:
            raise RuntimeError('Unsupported ONNX core optimization flag')
    return {'core_translation_units_checked':len(cxx),'jni_translation_units_checked':len(jni),
            'assembly_translation_units':sum(Path(e['file']).suffix.lower()=='.s' for e in core),
            'assembly_note':'Handwritten MLAS assembly produces native objects; LLVM bitcode ThinLTO does not apply to assembly.',
            'compile_database_sha256':sha256(path),
            'effective_core_and_jni_optimization':'-O3 -flto=thin','fast_math':False,
            'architecture_policy':'ARMv8-A generic code; optional upstream MLAS kernel flags and CPU feature dispatch are preserved, not forced on the whole library.',
            'cpu_dispatch_source':'onnxruntime/core/mlas/lib/platform.cpp at the pinned ONNX commit',
            'architecture_flags':sorted({a for args in commands for a in args if a.startswith(('-march=','-mcpu='))})}

def compile_c(name,sources,includes,defines,output,extra_libraries):
    _,_,tools,clang=toolchain()
    args=[clang,'-std=gnu17','-shared','-fPIC',*FLAGS,*['-I'+str(p) for p in includes],
          *['-D'+d for d in defines],*sources,*LINK,'-Wl,-soname,'+name,*extra_libraries,'-o',output]
    run(*args)
    verify_elf(output,tools)
    required=set(policy()['expected_exports'].get(name,[]))
    if not required or not required.issubset(symbols(output,tools)):
        raise RuntimeError('Source-built native API surface differs: '+name)
    return {'kind':'source-built','compiler':run(clang,'--version',capture=True).stdout.splitlines()[0],
            'compile_flags':FLAGS,'link_flags':LINK,'sources':[Path(p).name for p in sources],
            'sha256_before_android_strip':sha256(output),'build_id':build_id(output,tools)}

def sqlite_native(receipt):
    pin=policy()['sqlite'];archive=NATIVE/'sqlite-amalgamation.zip'
    if not archive.exists():download(pin['url'],archive,pin['sha256'])
    if sha256(archive)!=pin['sha256']:raise RuntimeError('SQLite source hash mismatch')
    with zipfile.ZipFile(archive) as z:source=z.read(pin['member'])
    if pin['source_id'].encode() not in source:raise RuntimeError('SQLite source identity mismatch')
    path=NATIVE/'sqlite3.c';path.write_bytes(source)
    package=ROOT/'.dart_tool/package_config.json'
    config=json.loads(package.read_text('utf-8'))
    from urllib.parse import urljoin,urlparse,unquote
    entry=next(x for x in config['packages'] if x['name']=='sqlite3')
    uri=urljoin(package.resolve().as_uri(),entry['rootUri'])
    pkg=Path(unquote(urlparse(uri).path))
    description=(pkg/'lib/src/hook/compile/description.dart').read_text('utf-8')
    match=re.search(r"const _defaultDefines = '''(.*?)''';",description,re.S)
    if not match:raise RuntimeError('SQLite compile options changed; review before building')
    defines=match.group(1).split()
    target=ROOT/'android/app/src/main/jniLibs/arm64-v8a/libsqlite3.so';target.parent.mkdir(parents=True,exist_ok=True)
    item=compile_c(target.name,[path],[],defines,target,['-lm','-ldl'])
    # The same amalgamation/options must retain database semantics before cross-compilation is shipped.
    host=NATIVE/'libsqlite3-host.so'
    run('cc','-std=gnu17','-shared','-fPIC','-O3','-fno-fast-math',*['-D'+d for d in defines],path,'-lm','-ldl','-o',host)
    run('python',ROOT/'.avx1/test_native_sqlite.py',host)
    receipt[target.name]={**item,'version':pin['version'],'source':pin['url'],'source_sha256':pin['sha256'],
                          'source_id':pin['source_id'],'license':'Public domain; preserved amalgamation notice',
                          'checks':['host SQL transactions/FTS5/JSON/integrity','AArch64 ELF','16 KiB pages']}
    notices=ROOT/'android/app/src/main/assets/avx1-native-notices';notices.mkdir(parents=True,exist_ok=True)
    (notices/'sqlite-public-domain.txt').write_text(source[:1800].decode('utf-8',errors='replace')+'\nSource: '+pin['url']+'\n',encoding='utf-8')

def jni_native(receipt):
    pin=policy()['jni'];source=pub_source(pin)/'src'
    config=ROOT/'.dart_tool/package_config.json'
    from urllib.parse import urljoin,urlparse,unquote
    entry=next(x for x in json.loads(config.read_text('utf-8'))['packages'] if x['name']=='jni')
    package=Path(unquote(urlparse(urljoin(config.resolve().as_uri(),entry['rootUri'])).path))
    gradle=package/'android/build.gradle';text=gradle.read_text('utf-8')
    needle='    externalNativeBuild {';start=text.find(needle)
    if start<0:raise RuntimeError('JNI Android build recipe changed; no blind patch')
    brace=text.find('{',start);depth=1;end=brace+1
    while depth:
        depth+=(text[end]=='{')-(text[end]=='}');end+=1
    gradle.write_text(text[:start]+'    // Native ARM64 library is built by the verified fork recipe.\n'+text[end:],encoding='utf-8',newline='\n')
    target=package/'android/src/main/jniLibs/arm64-v8a/libdartjni.so';target.parent.mkdir(parents=True,exist_ok=True)
    item=compile_c(target.name,[source/'dartjni.c',source/'third_party/global_jni_env.c',source/'include/dart_api_dl.c'],
                   [source,source/'include'],['DART_SHARED_LIB'],target,['-llog','-ldl'])
    receipt[target.name]={**item,'version':pin['version'],'source':pin['url'],'source_sha256':pin['sha256'],
                          'license':'BSD-3-Clause plus Apache-2.0 Android JNI definitions; notices retained','checks':['AArch64 ELF','16 KiB pages']}
    shutil.copy2(source.parent/'LICENSE',ROOT/'android/app/src/main/assets/avx1-native-notices/dartjni-LICENSE')
    shutil.copy2(ROOT/'.avx1/licenses/Apache-2.0.txt',ROOT/'android/app/src/main/assets/avx1-native-notices/dartjni-android-Apache-2.0.txt')
    (ROOT/'android/app/src/main/assets/avx1-native-notices/dartjni-android-NOTICE.txt').write_text(
        'Generated JNI environment bindings include Android JNI header definitions.\nCopyright (C) 2006 The Android Open Source Project.\nLicensed under Apache License 2.0; full license included alongside.\n',encoding='utf-8')

def onnx_native(receipt):
    pin=policy()['onnx'];source=NATIVE/'onnxruntime'
    if not source.exists():
        run('git','clone','--depth','1','--branch',pin['tag'],'--recurse-submodules','--shallow-submodules',pin['repository'],source)
    if run('git','rev-parse','HEAD',cwd=source,capture=True).stdout.strip()!=pin['commit']:
        raise RuntimeError('ONNX source differs from the pinned commit')
    run('git','diff','--exit-code',cwd=source)
    # The historical GitLab ZIP no longer matches the immutable ORT deps hash.
    # Fetch the identical upstream Git commit via its mirror, retaining source identity.
    eigen_pin=policy()['eigen'];eigen=NATIVE/'eigen'
    if not eigen.exists():
        run('git','init',eigen)
        run('git','remote','add','origin',eigen_pin['repository'],cwd=eigen)
        run('git','fetch','--depth','1','origin',eigen_pin['commit'],cwd=eigen)
        run('git','checkout','--detach','FETCH_HEAD',cwd=eigen)
    if run('git','rev-parse','HEAD',cwd=eigen,capture=True).stdout.strip()!=eigen_pin['commit']:
        raise RuntimeError('Eigen source differs from the exact ONNX dependency commit')
    run('git','diff','--exit-code',cwd=eigen)
    sdk,ndk,tools,clang=toolchain()
    build=NATIVE/'ort-build'
    release_flags=' '.join([*FLAGS])
    from native_cache_proof import verify_cache
    cache = verify_cache(ROOT, build, run(clang,'--version',capture=True).stdout.splitlines()[0])
    print('ONNX_NATIVE_CACHE='+json.dumps(cache),flush=True)
    if cache['status'] != 'reused':
      run('python',source/'tools/ci_build/build.py','--build_dir',build,'--config','Release','--android',
        '--android_abi','arm64-v8a','--android_api','24','--android_sdk_path',sdk,'--android_ndk_path',ndk,
        '--build_shared_lib','--build_java','--use_nnapi','--use_xnnpack','--enable_lto','--skip_tests',
        '--parallel','2','--cmake_generator','Ninja','--compile_no_warning_as_error',
        '--cmake_extra_defines','CMAKE_C_FLAGS_RELEASE='+release_flags,'CMAKE_CXX_FLAGS_RELEASE='+release_flags,
        'CMAKE_SHARED_LINKER_FLAGS='+' '.join(LINK),'CMAKE_EXPORT_COMPILE_COMMANDS=ON',
        'onnxruntime_BUILD_UNIT_TESTS=OFF',
        'ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON','ANDROID_STL=c++_static',
        'CMAKE_MAKE_PROGRAM='+shutil.which('ninja'),'FETCHCONTENT_SOURCE_DIR_EIGEN3='+str(eigen),cwd=source)
    compiler_evidence=onnx_compile_evidence(build)
    archive=NATIVE/'onnxruntime-original.aar';pom=NATIVE/'onnxruntime-original.pom'
    if not archive.exists():download(pin['aar_url'],archive,pin['aar_sha256'])
    if sha256(archive)!=pin['aar_sha256']:raise RuntimeError('Original ONNX AAR hash mismatch')
    if not pom.exists():download(pin['pom_url'],pom,pin['pom_sha256'])
    if sha256(pom)!=pin['pom_sha256']:raise RuntimeError('Original ONNX POM hash mismatch')
    replacements={}
    for name in ('libonnxruntime.so','libonnxruntime4j_jni.so'):
        paths=sorted(build.rglob(name),key=lambda p:len(str(p)))
        if not paths:raise RuntimeError('ONNX native output missing: '+name)
        target=paths[0];verify_elf(target,tools)
        with zipfile.ZipFile(archive) as original:
            before=NATIVE/('original-'+name);before.write_bytes(original.read('jni/arm64-v8a/'+name))
        required=symbols(before,tools)
        if name.endswith('4j_jni.so'):required={x for x in required if x.startswith(('Java_','JNI_'))}
        else:required={x for x in required if x.startswith('Ort')}
        if not required or not required.issubset(symbols(target,tools)):
            raise RuntimeError('ONNX public API/JNI exports changed: '+name)
        replacements['jni/arm64-v8a/'+name]=target.read_bytes()
        receipt[name]={'kind':'source-built','version':pin['version'],'source':pin['repository'],
                       'source_commit':pin['commit'],'compile_flags':FLAGS,'link_flags':LINK,
                       'compiler_command_evidence':compiler_evidence,'qualified_binary_cache':cache,
                       'providers':['CPU','NNAPI','XNNPACK'],'full_operator_build':True,
                       'checks':['original public API/JNI exports preserved','AArch64 ELF','16 KiB pages'],
                       'sha256_before_android_strip':sha256(target),'build_id':build_id(target,tools),
                       'license':'MIT and upstream ThirdPartyNotices preserved',
                       'third_party_sources':{'Eigen':{**eigen_pin,'license':'MPL-2.0; exact source commit retained'}}}
    repo=NATIVE/'maven/com/microsoft/onnxruntime/onnxruntime-android'/pin['version'];repo.mkdir(parents=True,exist_ok=True)
    aar=repo/f"onnxruntime-android-{pin['version']}.aar"
    with zipfile.ZipFile(archive) as original,zipfile.ZipFile(aar,'w',zipfile.ZIP_DEFLATED) as output:
        for entry in original.infolist():
            if entry.filename.startswith('jni/') and not entry.filename.startswith('jni/arm64-v8a/'):continue
            output.writestr(entry.filename,replacements.get(entry.filename,original.read(entry)))
    shutil.copy2(pom,repo/f"onnxruntime-android-{pin['version']}.pom")
    notices=ROOT/'android/app/src/main/assets/avx1-native-notices';notices.mkdir(parents=True,exist_ok=True)
    for name in ('LICENSE','ThirdPartyNotices.txt','ThirdPartyNotices.md'):
        p=source/name
        if p.is_file():shutil.copy2(p,notices/('onnxruntime-'+name))
    shutil.copy2(eigen/'COPYING.MPL2',notices/'Eigen-COPYING.MPL2')
    (notices/'Eigen-source.txt').write_text(eigen_pin['repository']+'\nCommit: '+eigen_pin['commit']+'\n',encoding='utf-8')

def prepare():
    NATIVE.mkdir(parents=True,exist_ok=True)
    vendor_notices()
    receipt={}
    for builder in (sqlite_native,jni_native,onnx_native):
        builder(receipt)
        (NATIVE/'build-receipt.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
    return receipt

def inventory(apk,receipt):
    _,_,tools,_=toolchain();pins=policy()
    result={}
    with zipfile.ZipFile(apk) as archive:
        required_notices={'assets/avx1-native-notices/'+n for n in ('WebRTC-WEBRTC.md','PDFium-LICENSE',
            'dartjni-LICENSE','dartjni-android-Apache-2.0.txt','onnxruntime-LICENSE','Eigen-COPYING.MPL2','Silero-VAD-MIT.txt')}
        if not required_notices.issubset(archive.namelist()):raise RuntimeError('APK native license notices are missing')
        if archive.read('META-INF/androidx.datastore_datastore-core.version').decode().strip()!=pins['datastore_version']:
            raise RuntimeError('DataStore native component version changed')
        for member in archive.namelist():
            if not member.startswith('lib/arm64-v8a/') or not member.endswith('.so'):continue
            name=Path(member).name;binary=NATIVE/('packaged-'+name);binary.write_bytes(archive.read(member))
            verify_elf(binary,tools)
            item=receipt.get(name)
            if item is None:
                item=pins['other_libraries'].get(name)
                if item is None:raise RuntimeError('Unreviewed native APK library: '+name)
                item=dict(item)
                if name in ('libflutter.so','libapp.so'):
                    toolchains=json.loads((ROOT/'.avx1/toolchains.json').read_text('utf-8'))
                    item.update(flutter_version=toolchains['flutter_version'],flutter_source_commit=toolchains['flutter_sha'])
                if name=='libflutter.so':item.update(flutter_reference(tools))
            elif build_id(binary,tools)!=item['build_id']:
                raise RuntimeError('APK contains a different native build: '+name)
            required=set(pins['expected_exports'].get(name,[]))
            if required and not required.issubset(symbols(binary,tools)):
                raise RuntimeError('Packaged native exports changed: '+name)
            result[name]={**item,'packaged_sha256':sha256(binary),'packaged_bytes':binary.stat().st_size}
            expected=item.get('expected_packaged_sha256')
            if expected and result[name]['packaged_sha256']!=expected:
                raise RuntimeError('Unchanged vendor native binary changed; review provenance: '+name)
    if not set(receipt).issubset(result):raise RuntimeError('A rebuilt library was not packaged')
    platform={'libc.so','libm.so','libdl.so','liblog.so','libandroid.so','libz.so','libEGL.so','libGLESv2.so',
              'libGLESv3.so','libOpenSLES.so','libvulkan.so','libaaudio.so','libjnigraphics.so'}
    for name in receipt:
        dynamic=run(tools/'llvm-readelf','-d',NATIVE/('packaged-'+name),capture=True).stdout
        needed=re.findall(r'\(NEEDED\).*?\[([^\]]+)\]',dynamic)
        if set(needed)-platform-set(result):raise RuntimeError('Rebuilt native library has an unbundled dependency: '+name)
        result[name]['needed_libraries']=needed
    return {'abi':'arm64-v8a','baseline':'ARMv8-A','pgo':False,'fast_math_requested':False,
            'source_built_native_libraries':sorted(receipt),'libraries':result,
            'vendor_notice_sources':{'WebRTC':pins['webrtc_vendor'],'PDFium':pins['pdfium_vendor']},
            'bundled_upstream_vad':pins['bundled_vad'],
            'physical_device_speedup_percent':None}
