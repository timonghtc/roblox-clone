$listener = New-Object System.Net.HttpListener;
$listener.Prefixes.Add("http://localhost:8000/");
$listener.Start();
Write-Host "Server started at http://localhost:8000/";
Write-Host "Logs will be saved to logs.json";

if (-not (Test-Path "logs.json")) {
    "[]" | Out-File -FilePath "logs.json" -Encoding utf8
}

while ($listener.IsListening) {
    $context = $listener.GetContext();
    $request = $context.Request;
    $response = $context.Response;
    $url = $request.Url.LocalPath;

    if ($url -eq "/") { $url = "/index.html" }

    if ($request.HttpMethod -eq "POST" -and $url -eq "/log") {
        # Handle logging
        $reader = New-Object System.IO.StreamReader($request.InputStream);
        $body = $reader.ReadToEnd();
        $reader.Close();

        Write-Host "Received log: $body";

        try {
            $logEntry = $body | ConvertFrom-Json
            $logEntry | Add-Member -MemberType NoteProperty -Name "ip" -Value $request.RemoteEndPoint.Address.ToString()
            $logEntry | Add-Member -MemberType NoteProperty -Name "timestamp" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            $logEntry | Add-Member -MemberType NoteProperty -Name "userAgent" -Value $request.UserAgent

            $currentLogs = Get-Content "logs.json" -Raw | ConvertFrom-Json
            if ($null -eq $currentLogs) { $currentLogs = @() }
            $currentLogs += $logEntry
            $currentLogs | ConvertTo-Json -Depth 10 | Out-File -FilePath "logs.json" -Encoding utf8

            $response.StatusCode = 200;
            $buffer = [System.Text.Encoding]::UTF8.GetBytes("Log recorded");
            $response.OutputStream.Write($buffer, 0, $buffer.Length);
        } catch {
            $response.StatusCode = 400;
            $buffer = [System.Text.Encoding]::UTF8.GetBytes("Invalid JSON");
            $response.OutputStream.Write($buffer, 0, $buffer.Length);
        }
    } else {
        # Serve static files
        $filePath = Join-Path (Get-Location) $url.Replace("/", "\").TrimStart("\");
        if (Test-Path $filePath -PathType Leaf) {
            $bytes = [System.IO.File]::ReadAllBytes($filePath);
            
            # Set Content-Type
            if ($filePath.EndsWith(".html")) { $response.ContentType = "text/html" }
            elseif ($filePath.EndsWith(".css")) { $response.ContentType = "text/css" }
            elseif ($filePath.EndsWith(".js")) { $response.ContentType = "application/javascript" }
            elseif ($filePath.EndsWith(".json")) { $response.ContentType = "application/json" }
            elseif ($filePath.EndsWith(".png")) { $response.ContentType = "image/png" }
            elseif ($filePath.EndsWith(".jpg") -or $filePath.EndsWith(".jpeg")) { $response.ContentType = "image/jpeg" }
            
            $response.ContentLength64 = $bytes.Length;
            $response.OutputStream.Write($bytes, 0, $bytes.Length);
        } else {
            $response.StatusCode = 404;
            $buffer = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $url");
            $response.OutputStream.Write($buffer, 0, $buffer.Length);
        }
    }
    $response.Close();
}
