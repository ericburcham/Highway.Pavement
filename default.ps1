Framework "4.0"

properties {
    $build_config = "Release"
    $solution_info_path = ".\src\Highway.Pavement\SolutionInfo.cs"
    $pack_dir = ".\pack"
    $build_archive = ".\buildarchive"
    $version_number = "0.4.0.0"
    $nuget_version_number = $version_number
    if ($Env:BUILD_NUMBER -ne $null) {
        $nuget_version_number += "-$Env:BUILD_NUMBER"
    }
}

task default -depends build
task build -depends build-all
task test -depends build-all, test-all, pack-ci
task pack -depends pack-all
task push -depends push-all


task test-all -depends clean-buildarchive, Clean-TestResults {
    $mstest = Get-ChildItem -Recurse -Force 'C:\Program Files (x86)\Microsoft Visual Studio 12.0\Common7\IDE\MSTest.exe'
    $mstest = $mstest.FullName
    $test_dlls = Get-ChildItem -Recurse ".\src\**\**\bin\release\*Tests.dll" |
        ?{ $_.Directory.Parent.Parent.Name -eq ($_.Name.replace(".dll","")) }
    $test_dlls | % { 
        try {
            exec { & "$mstest" /testcontainer:$($_.FullName) } 
        } finally {
            cp .\TestResults\*.trx $build_archive -Verbose
        }
    }
}

task build-all -depends Update-Version {
    rebuild .\src\Highway.Pavement\Highway.Pavement.sln
}

task pack-ci -depends clean-buildarchive, pack-all -precondition { Test-IsCI } {
    dir -Path "$pack_dir\*.nupkg" | % { 
        cp $_ $build_archive
    } 
}

task pack-all -depends Update-Version, clean-nuget -precondition { Test-PackageDoesNotExist } {
	pack-nuget .\src\Highway.Pavement\Highway.Pavement\Highway.Pavement.csproj
}

task push-all -depends pack-all, clean-nuget {
    Get-ChildItem -Path "$pack_dir\*.nupkg" |
        %{ 
            push-nuget $_
            mv $_ .\nuget\.
        }
    rm $pack_dir -Recurse -Force
}


task clean-buildarchive {
    Reset-Directory $build_archive
}

task clean-nuget {
    Reset-Directory $pack_dir
}

task clean-testresults {
    Reset-Directory .\TestResults
}

task Update-Version {
    $solution_info = Get-Content $solution_info_path
    $solution_info = $solution_info -replace 'Version\(".+"\)', "Version(`"$version_number`")"
    $solution_info = $solution_info -replace 'AssemblyFileVersion\(".+"\)', "AssemblyFileVersion(`"$nuget_version_number`")"
    $solution_info = $solution_info -replace 'AssemblyInformationalVersion\(".+"\)', "AssemblyInformationalVersion(`"$nuget_version_number`")"
    Set-Content -Path $solution_info_path -Value $solution_info
    if (Test-ModifiedInGIT $solution_info_path) {
        Write-Warning "SolutionInfo.cs changed, most likely updating to a new version"
    }
}

##########################################################################################
# Functions
##########################################################################################

function Test-IsCI {
    $Env:TEAMCITY_VERSION -ne $null
}

function Test-PackageDoesNotExist() {
    (ls ".\nuget\*$version_number.nupkg" | Measure-Object).Count -gt 0
}

function Test-ModifiedInGIT($path) {
    if (Test-IsCI -eq $false) { return $false }
    $status_result = & git status $path --porcelain
    $status_result -ne $null
}

function Reset-Directory($path) {
    if (Test-Path $path) {
        Remove-item $path -Recurse -Force
    }
    if (PathDoesNotExist $path) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}


function rebuild([string]$slnPath) { 
    Set-Content Env:\EnableNuGetPackageRestore -Value true
    .\src\Highway.Pavement\.nuget\NuGet.exe restore $slnPath
    exec { msbuild $slnPath /t:rebuild /v:q /clp:ErrorsOnly /nologo /p:Configuration=$build_config }
}

function pack-nuget($prj) {
    exec { 
        & .\src\Highway.Pavement\.nuget\nuget.exe pack $prj -o pack -prop configuration=$build_config
    }
}

function push-nuget($prj) {
    exec { 
        & .\src\Highway.Pavement\.nuget\nuget.exe push $prj
    }
}

function PathDoesNotExist($path) {
    (Test-Path $path) -eq $false
}
