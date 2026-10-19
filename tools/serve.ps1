# Cubeborn local static dev server (no Node/Python needed)
# Usage: powershell -ExecutionPolicy Bypass -File tools/serve.ps1 [-Port 5173]
param([int]$Port = 5173)

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'text/javascript; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.md'   = 'text/plain; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.wav'  = 'audio/wav'
    '.mp3'  = 'audio/mpeg'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Cubeborn dev server: http://localhost:$Port/  (Ctrl+C to stop)"

try {
    while ($listener.IsListening) {
        $task = $listener.GetContextAsync()
        while (-not $task.AsyncWaitHandle.WaitOne(200)) { }
        $ctx = $task.GetAwaiter().GetResult()
        $res = $ctx.Response
        try {
            $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
            if ([string]::IsNullOrEmpty($rel)) { $rel = 'index.html' }
            $path = [IO.Path]::GetFullPath((Join-Path $root $rel))
            if ($path.StartsWith($root) -and [IO.File]::Exists($path)) {
                $bytes = [IO.File]::ReadAllBytes($path)
                $type = $mime[[IO.Path]::GetExtension($path).ToLower()]
                if (-not $type) { $type = 'application/octet-stream' }
                $res.ContentType = $type
            } else {
                $res.StatusCode = 404
                $bytes = [Text.Encoding]::UTF8.GetBytes('404 Not Found')
            }
            $res.Headers.Add('Cache-Control', 'no-store')
            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
        } catch {
            Write-Host "Error: $_"
        } finally {
            $res.Close()
        }
    }
} finally {
    $listener.Stop()
}
