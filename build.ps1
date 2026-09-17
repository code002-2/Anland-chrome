# build.ps1 —— 本机一键编译 appwrap
#
# 与 anland 仓库同一套工具链：AGP 9.4.0 / Gradle 9.6.0 / JDK 17 / compileSdk 36。
# 首次运行会下载 Gradle 发行包与 AGP 依赖（需要网络）。
#
# 用法:  .\build.ps1            # assembleRelease
#        .\build.ps1 clean      # 先清理
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not $env:JAVA_HOME) {
    foreach ($c in @('C:\Program Files\Java\jdk-17', 'C:\Program Files\Java\jdk-21')) {
        if (Test-Path $c) { $env:JAVA_HOME = $c; break }
    }
}
if (-not $env:JAVA_HOME) { throw '找不到 JDK：请设置 JAVA_HOME（需要 17+）' }

if (-not $env:ANDROID_HOME) {
    $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    if (Test-Path $sdk) { $env:ANDROID_HOME = $sdk }
}
if (-not $env:ANDROID_HOME) { throw '找不到 Android SDK：请设置 ANDROID_HOME' }

Write-Host "JAVA_HOME   = $env:JAVA_HOME"
Write-Host "ANDROID_HOME= $env:ANDROID_HOME"

# 1) 签名用的 debug keystore（gitignore；与 anland 仓库同一套口令/别名，方便覆盖安装自己的构建）
$ks = Join-Path $PSScriptRoot 'debug.keystore'
if (-not (Test-Path $ks)) {
    Write-Host '生成 debug.keystore ...'
    & "$env:JAVA_HOME\bin\keytool.exe" -genkeypair -keystore $ks -alias anland `
        -storepass anland -keypass anland -keyalg RSA -keysize 2048 -validity 10000 `
        -dname 'CN=AppWrap Debug' | Out-Null
}

# 2) libawl 的 AAR（无 Maven 发布，必须手工放入 libs/）
$aar = Join-Path $PSScriptRoot 'libs\anland-awllib.aar'
if (-not (Test-Path $aar)) {
    throw "缺少 $aar —— 从 anland 的 CI 产物 anland-build.zip / GitHub Release 里的 anland-awllib.aar，或本机 make apk 的 build/anland-awllib.aar 拷进 libs\\"
}
Write-Host ("libawl AAR  = {0:N0} bytes  ({1})" -f (Get-Item $aar).Length, (Get-FileHash $aar -Algorithm SHA256).Hash.Substring(0, 12))

# 3) 直接用 wrapper jar 调 Gradle（本工程没有 gradlew.bat，Windows 上这样最省事；
#    wrapper 会按 gradle/wrapper/gradle-wrapper.properties 下载 Gradle 9.6.0）
$wrapper = Join-Path $PSScriptRoot 'gradle\wrapper\gradle-wrapper.jar'
if (-not (Test-Path $wrapper)) { throw "缺少 $wrapper" }

$tasks = if ($args.Count -gt 0) { $args } else { @('assembleRelease') }
& "$env:JAVA_HOME\bin\java.exe" -classpath $wrapper org.gradle.wrapper.GradleWrapperMain @tasks
if ($LASTEXITCODE -ne 0) { throw "gradle 失败 (exit $LASTEXITCODE)" }

# 产物名取自 rootProject.name（settings.gradle 里是 anland-appwrap）
$apk = Join-Path $PSScriptRoot 'build\outputs\apk\release\anland-appwrap-release.apk'
if (Test-Path $apk) {
    Write-Host ''
    Write-Host ("OK: {0}  ({1:N0} bytes)" -f $apk, (Get-Item $apk).Length)
    Write-Host '安装: adb install -r "' + $apk + '"'
}
