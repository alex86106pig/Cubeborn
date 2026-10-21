# Local static server for testing the Godot web export (build/web); no Node/Python needed
# Usage: powershell -ExecutionPolicy Bypass -File tools/serve_web.ps1 [-Port 8060]
# .wasm must be served as application/wasm for streaming compilation
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI
param([int]$Port = 8060)

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\build\web')).Path
$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'text/javascript; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.wasm' = 'application/wasm'
    '.pck'  = 'application/octet-stream'
    '.png'  = 'image/png'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Cubeborn web build: http://localhost:$Port/  (Ctrl+C to stop)"

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart('/')
        if ($path -eq '' -or $path.EndsWith('/')) { $path += 'index.html' }
        $file = Join-Path $root $path
        if ((Test-Path $file -PathType Leaf) -and ((Resolve-Path $file).Path.StartsWith($root))) {
            $bytes = [System.IO.File]::ReadAllBytes($file)
            $ext = [System.IO.Path]::GetExtension($file).ToLower()
            $ctx.Response.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
            $ctx.Response.ContentLength64 = $bytes.Length
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $ctx.Response.StatusCode = 404
        }
        $ctx.Response.Close()
    }
} finally {
    $listener.Stop()
}
