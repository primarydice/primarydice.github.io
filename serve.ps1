# 会社サイトをパソコンの中だけで表示して確認するための簡易サーバー
#
# 使い方: powershell -ExecutionPolicy Bypass -File serve.ps1 [-Port 8140]
#
# 起動したら、ブラウザで http://localhost:8140/ を開いてください。
# このウィンドウは開いたままにしておきます(閉じるとサーバーが止まります)。
# 止めるときは Ctrl + C を押してください。
#
# ※ これは確認用です。実際の公開は GitHub Pages が行うので、
#    このファイルをアップロードしても使われません(README.md 参照)。

param([int]$Port = 8140)

# PORT(環境変数 = 起動時に外から渡される番号)が指定されていれば、そちらを優先する
if ($env:PORT) { $Port = [int]$env:PORT }

$root = $PSScriptRoot
$mime = @{
  ".html"        = "text/html; charset=utf-8"
  ".css"         = "text/css; charset=utf-8"
  ".js"          = "text/javascript; charset=utf-8"
  ".json"        = "application/json; charset=utf-8"
  ".webmanifest" = "application/manifest+json; charset=utf-8"
  ".xml"         = "application/xml; charset=utf-8"
  ".txt"         = "text/plain; charset=utf-8"
  ".png"         = "image/png"
  ".jpg"         = "image/jpeg"
  ".jpeg"        = "image/jpeg"
  ".webp"        = "image/webp"
  ".svg"         = "image/svg+xml"
  ".ico"         = "image/x-icon"
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serving $root at http://localhost:$Port/"

while ($listener.IsListening) {
  $ctx  = $listener.GetContext()
  $path = [System.Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath)

  # GitHub Pages と同じく、フォルダ名で終わる URL は中の index.html を返す
  if ($path.EndsWith("/")) { $path += "index.html" }

  $file = Join-Path $root ($path -replace "/", "\").TrimStart("\")
  try {
    if ((Test-Path $file -PathType Leaf) -and ((Resolve-Path $file).Path.StartsWith($root))) {
      $bytes = [System.IO.File]::ReadAllBytes($file)
      $ext = [System.IO.Path]::GetExtension($file).ToLower()
      $ctx.Response.ContentType = if ($mime[$ext]) { $mime[$ext] } else { "application/octet-stream" }
      $ctx.Response.Headers.Add("Cache-Control", "no-store")
      $ctx.Response.ContentLength64 = $bytes.Length
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      # 見つからないときは 404.html を返す(GitHub Pages と同じ動き)
      $notFound = Join-Path $root "404.html"
      $ctx.Response.StatusCode = 404
      if (Test-Path $notFound -PathType Leaf) {
        $bytes = [System.IO.File]::ReadAllBytes($notFound)
        $ctx.Response.ContentType = "text/html; charset=utf-8"
        $ctx.Response.ContentLength64 = $bytes.Length
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
      }
    }
  } catch {
    $ctx.Response.StatusCode = 500
  }
  $ctx.Response.OutputStream.Close()
}
