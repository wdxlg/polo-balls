# Run manually in PowerShell with VS C++ build tools, Python and Git installed.
# Uses a separate tool directory; never replaces the Steam Godot installation.
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$tools = Join-Path (Split-Path $project -Parent) 'polo-balls-tools/offline-engine'
New-Item -ItemType Directory -Force $tools | Out-Null
$archive = Join-Path $tools 'godot-ed1daf0bf.tar.gz'
if (!(Test-Path $archive)) {
    Invoke-WebRequest 'https://codeload.github.com/godotengine/godot/tar.gz/ed1daf0bf' -OutFile $archive
}
$manifest = Get-Content (Join-Path $PSScriptRoot 'build_manifest.json') -Raw | ConvertFrom-Json
if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLower() -ne $manifest.source_archive_sha256) {
    throw 'Source archive hash mismatch. Do not build unverified sources.'
}
$source = Join-Path $tools 'godot-ed1daf0bf'
if (!(Test-Path $source)) {
    tar -xf $archive -C $tools
    if ($LASTEXITCODE -ne 0) { throw 'Source extraction failed.' }
}
$oldPythonPath = $env:PYTHONPATH
try {
    python -m pip install --target (Join-Path $tools 'python') scons
    if ($LASTEXITCODE -ne 0) { throw 'SCons installation failed.' }
    $env:PYTHONPATH = (Join-Path $tools 'python')
    Push-Location $source
    try {
        # Windows PowerShell 5 may promote native stderr to a terminating error.
        $oldErrorPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { git apply --reverse --check (Join-Path $PSScriptRoot 'engine.patch') 2>$null; $alreadyApplied = ($LASTEXITCODE -eq 0) }
        finally { $ErrorActionPreference = $oldErrorPreference }
        if (!$alreadyApplied) {
            git apply --check (Join-Path $PSScriptRoot 'engine.patch')
            if ($LASTEXITCODE -ne 0) { throw 'Source tree does not match patch; refusing overwrite.' }
            git apply (Join-Path $PSScriptRoot 'engine.patch')
            if ($LASTEXITCODE -ne 0) { throw 'Patch failed.' }
        }
        python misc/scripts/install_d3d12_sdk_windows.py
        if ($LASTEXITCODE -ne 0) { throw 'D3D12 dependencies failed.' }
        python -m SCons platform=windows target=editor arch=x86_64 d3d12=yes production=yes lto=none debug_symbols=no -j8
        if ($LASTEXITCODE -ne 0) { throw 'Godot compilation failed.' }
        $runtime = Join-Path $tools 'runtime'
        New-Item -ItemType Directory -Force $runtime | Out-Null
        Copy-Item bin/godot.windows.editor.x86_64.exe (Join-Path $runtime 'Godot.4.7.2.offline.exe')
        Copy-Item bin/*.dll $runtime -Force
        Copy-Item LICENSE.txt,COPYRIGHT.txt $runtime -Force
        # Rebuilt binaries can differ from the shipped build: write their actual hashes.
        $manifest.files = @{}
        foreach ($name in @('Godot.4.7.2.offline.exe','D3D12Core.dll','d3d12SDKLayers.dll','LICENSE.txt','COPYRIGHT.txt')) {
            $manifest.files[$name] = (Get-FileHash (Join-Path $runtime $name) -Algorithm SHA256).Hash.ToLower()
        }
        $manifest.runtime_path = $runtime
        $manifest.patch_sha256 = (Get-FileHash (Join-Path $PSScriptRoot 'engine.patch') -Algorithm SHA256).Hash.ToLower()
        $manifest | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $runtime 'build_manifest.json') -Encoding UTF8
    } finally { Pop-Location }
} finally { $env:PYTHONPATH = $oldPythonPath }
Write-Host "Built independent runtime: $tools/runtime"
