$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$Port = if ($args.Count -gt 0) { [int]$args[0] } else { 5173 }
$ContentTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".css" = "text/css; charset=utf-8"
    ".js" = "application/javascript; charset=utf-8"
    ".yaml" = "text/yaml; charset=utf-8"
    ".yml" = "text/yaml; charset=utf-8"
    ".png" = "image/png"
    ".jpg" = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".gif" = "image/gif"
    ".svg" = "image/svg+xml"
    ".pdf" = "application/pdf"
}

function Send-Response {
    param (
        [Net.Sockets.NetworkStream]$Stream,
        [string]$Status,
        [string]$ContentType,
        [byte[]]$Body,
        [string]$ExtraHeaders = ""
    )

    $header = "HTTP/1.1 $Status`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`n$ExtraHeaders" +
        "Cache-Control: no-store, no-cache, must-revalidate, max-age=0`r`nPragma: no-cache`r`nExpires: 0`r`nConnection: close`r`n`r`n"
    $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    $Stream.Write($Body, 0, $Body.Length)
}

function Get-Version {
    $latest = Get-ChildItem -LiteralPath $Root -Recurse -File |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if ($latest) {
        return $latest.LastWriteTimeUtc.Ticks.ToString()
    }

    return "0"
}

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse("127.0.0.1"), $Port)
$listener.Start()
Write-Host "Serving $Root at http://127.0.0.1:$Port/"

while ($true) {
    $client = $listener.AcceptTcpClient()

    try {
        $stream = $client.GetStream()
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::ASCII)
        $requestLine = $reader.ReadLine()

        while ($true) {
            $line = $reader.ReadLine()
            if ([string]::IsNullOrEmpty($line)) {
                break
            }
        }

        $url = if ($requestLine -match "^GET\s+([^\s]+)") { $matches[1] } else { "/" }
        $path = [Uri]::UnescapeDataString(($url -split "\?")[0].TrimStart("/"))

        if ([string]::IsNullOrWhiteSpace($path)) {
            $path = "index.html"
        }

        if ($path -eq "__version") {
            Send-Response $stream "200 OK" "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes((Get-Version)))
            continue
        }

        $fullPath = [IO.Path]::GetFullPath([IO.Path]::Combine($Root, $path))

        if (-not $fullPath.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) {
            Send-Response $stream "403 Forbidden" "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes("Forbidden"))
        } elseif (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $extension = [IO.Path]::GetExtension($fullPath).ToLowerInvariant()
            $contentType = if ($ContentTypes.ContainsKey($extension)) { $ContentTypes[$extension] } else { "application/octet-stream" }
            $extraHeaders = if ($extension -eq ".pdf") { "Content-Disposition: inline`r`n" } else { "" }
            Send-Response $stream "200 OK" $contentType ([IO.File]::ReadAllBytes($fullPath)) $extraHeaders
        } else {
            Send-Response $stream "404 Not Found" "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes("Not Found"))
        }
    } finally {
        $client.Close()
    }
}
