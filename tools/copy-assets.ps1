# 各アプリのアイコンとスクリーンショットを、サイト用に縮小してコピーするスクリプト
#
# 使い方: powershell -ExecutionPolicy Bypass -File tools\copy-assets.ps1
#
# 元の画像は Google Play 提出用なので大きすぎます(1080×2340 など)。
# そのままサイトに置くと表示が遅くなるので、横幅540ピクセルに縮めます。
# 画面上では約270ピクセルで表示するので、高精細画面(Retina など)でも
# ぼやけない大きさです。何度実行しても同じ結果になります。

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root    = Split-Path -Parent $PSScriptRoot
$srcRoot = Split-Path -Parent $root          # デスクトップ\クロード
$dstRoot = Join-Path $root 'assets\apps'

# コピー元 → コピー先 の対応表
$apps = @(
    @{
        name = 'manelog'
        icon = '家計簿\store-assets\play-store-icon-512.png'
        dir  = '家計簿\store-assets\screenshots'
        shots = @('01-receipt.png','02-subscription.png','03-custom.png','04-card.png','05-chart.png','06-calendar.png')
    },
    @{
        name = 'kawase'
        icon = 'かわせるん\store-assets\store-icon-512.png'
        dir  = 'かわせるん\store-assets\screenshots'
        shots = @('01-換算画面.png','02-単価計算.png','03-物価くらべ.png')
    },
    @{
        name = 'ratehunt'
        icon = '両替所さがし\store-assets\store-icon-512.png'
        dir  = '両替所さがし\store-assets\screenshots'
        shots = @('01-手数料の目安.png','02-8都市から選ぶ.png','03-空港での動き方.png','05-地図でさがす.png')
    },
    @{
        name = 'mielupe'
        icon = 'ミエルーペ\store\icon-512.png'
        dir  = 'ミエルーペ\store\screenshots'
        shots = @()   # ストア用の宣伝画像しか無いので、サイトではアイコンだけ使う
    }
)

function Save-Resized {
    param([string]$In, [string]$Out, [int]$MaxWidth, [string]$Format = 'png', [int]$Quality = 86)

    $img = [System.Drawing.Image]::FromFile($In)
    try {
        $w = $img.Width; $h = $img.Height
        if ($w -gt $MaxWidth) {
            $h = [int]([Math]::Round($h * $MaxWidth / $w))
            $w = $MaxWidth
        }
        $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                if ($Format -eq 'jpg') { $g.Clear([System.Drawing.Color]::White) }
                $g.DrawImage($img, 0, 0, $w, $h)
            } finally { $g.Dispose() }

            if ($Format -eq 'jpg') {
                $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
                $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
                $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$Quality)
                $bmp.Save($Out, $codec, $ep)
                $ep.Dispose()
            } else {
                $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
            }
        } finally { $bmp.Dispose() }
    } finally { $img.Dispose() }
}

foreach ($app in $apps) {
    $dst = Join-Path $dstRoot $app.name
    if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }

    # アイコン: カードで 64〜96px 表示なので 192px あれば十分
    $iconSrc = Join-Path $srcRoot $app.icon
    if (-not (Test-Path $iconSrc)) { throw "アイコンが見つかりません: $iconSrc" }
    Save-Resized -In $iconSrc -Out (Join-Path $dst 'icon.png') -MaxWidth 192

    # スクリーンショット
    $n = 0
    foreach ($s in $app.shots) {
        $n++
        $src = Join-Path $srcRoot (Join-Path $app.dir $s)
        if (-not (Test-Path $src)) { Write-Warning "見つかりません(飛ばします): $src"; continue }

        $outPng = Join-Path $dst ("shot-{0:00}.png" -f $n)
        Save-Resized -In $src -Out $outPng -MaxWidth 540

        # 写真のような画像は PNG だと重くなる。300KB を超えたら JPEG に切り替える
        if ((Get-Item $outPng).Length -gt 300KB) {
            $outJpg = Join-Path $dst ("shot-{0:00}.jpg" -f $n)
            Save-Resized -In $src -Out $outJpg -MaxWidth 540 -Format 'jpg' -Quality 86
            Remove-Item $outPng -Force
            Write-Host ("  {0} shot-{1:00}.jpg ({2}KB) ← PNGが重かったのでJPEGにしました" -f $app.name, $n, [int]((Get-Item $outJpg).Length/1KB))
        } else {
            Write-Host ("  {0} shot-{1:00}.png ({2}KB)" -f $app.name, $n, [int]((Get-Item $outPng).Length/1KB))
        }
    }
    Write-Host "$($app.name) 完了"
}

Write-Host ""
$total = (Get-ChildItem $dstRoot -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ("素材の合計サイズ: {0}KB" -f [int]($total/1KB))
