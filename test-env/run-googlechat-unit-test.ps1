Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$project = "c:\OLDD\Duress\_external\DuressServer2025\DuressServer2025.Tests\DuressServer2025.Tests.csproj"
$testExe = "c:\OLDD\Duress\_external\DuressServer2025\DuressServer2025.Tests\bin\Release\DuressServer2025.Tests.exe"
$msbuild = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"

& $msbuild $project /t:Build /p:Configuration=Release /p:Platform=AnyCPU
& $testExe
