# ロゴの黒背景を「透過」に変換し、favicon も作るスクリプト
#
# 使い方: powershell -ExecutionPolicy Bypass -File tools\make-logo.ps1
#
# ------------------------------------------------------------------
# なにをしているか
# ------------------------------------------------------------------
# 元の 会社ロゴ.png は「黒い長方形の中にロゴが描いてある」画像で、
# 透過(背景が透ける状態)になっていません。そのままサイトに置くと、
# 背景色が真っ黒でないかぎり、ロゴの周りに四角い枠が見えてしまいます。
#
# このロゴは「黒の上に銀色(無彩色)」という条件なので、
# 画像編集ソフトや外部サービスを使わなくても、計算だけで正確に透過できます。
#
#   各ピクセルについて
#     不透明度 a = そのピクセルの明るさ (R,G,B のうち一番大きい値)
#     色       = 元の色 ÷ a          (「アンプリマルチプライ」といいます)
#
# こうすると、黒い背景に重ねたときの見え方が元とまったく同じになり、
# なおかつ好きな暗い色の背景にも自然に乗るようになります。
#
# 何度でも実行できます(元ファイルは変更しません)。
# ------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root    = Split-Path -Parent $PSScriptRoot
$outDir  = Join-Path $root 'assets'
$logoOut = Join-Path $outDir 'logo.png'
$markOut = Join-Path $outDir 'mark.png'
$iconOut = Join-Path $outDir 'favicon.png'

# ---- 元になるロゴ画像を探す ----
# ファイル名が変わっても動くように、候補を順に探します。
$srcPath = $null
foreach ($name in @('会社ロゴ２.png', '会社ロゴ2.png', '会社ロゴ.png')) {
    $try = Join-Path $root $name
    if (Test-Path $try) { $srcPath = $try; break }
}
if (-not $srcPath) {
    $srcPath = Get-ChildItem $root -Filter '*ロゴ*.png' -File | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $srcPath) { throw "元のロゴ画像が $root に見つかりません" }
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
Write-Host "元にする画像: $(Split-Path $srcPath -Leaf)"

# ---- 画像処理の本体(C#)。PowerShell で1ピクセルずつ回すと遅いため ----
$cs = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class LogoTools
{
    // 黒背景の上に描かれた画像を透過PNGに変換する
    public static void Unpremultiply(string inPath, string outPath)
    {
        using (Bitmap src = new Bitmap(inPath))
        {
            int w = src.Width, h = src.Height;
            using (Bitmap dst = new Bitmap(w, h, PixelFormat.Format32bppArgb))
            {
                Rectangle r = new Rectangle(0, 0, w, h);
                BitmapData sd = src.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                BitmapData dd = dst.LockBits(r, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                int n = Math.Abs(sd.Stride) * h;
                byte[] buf = new byte[n];
                Marshal.Copy(sd.Scan0, buf, 0, n);
                // メモリ上の並びは B, G, R, A の順
                for (int i = 0; i < n; i += 4)
                {
                    int b = buf[i], g = buf[i + 1], rr = buf[i + 2];
                    int a = Math.Max(rr, Math.Max(g, b));
                    if (a == 0)
                    {
                        buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = 0;
                    }
                    else
                    {
                        buf[i]     = (byte)(b  * 255 / a);
                        buf[i + 1] = (byte)(g  * 255 / a);
                        buf[i + 2] = (byte)(rr * 255 / a);
                        buf[i + 3] = (byte)a;
                    }
                }
                Marshal.Copy(buf, 0, dd.Scan0, n);
                src.UnlockBits(sd);
                dst.UnlockBits(dd);
                dst.Save(outPath, ImageFormat.Png);
            }
        }
    }

    // 透過PNGの「透明なふち」を切り落とす。
    // 元のロゴは上に93px・下に48px・左に118px・右に100px と、余白が左右上下でバラバラ。
    // そのまま中央寄せすると、絵そのものは中央からずれて見える。
    // ここで余白を全部落としておけば、あとはCSSの中央寄せがそのまま正しくなる。
    public static int[] Trim(string path, int alphaThreshold)
    {
        int[] box;
        using (Bitmap src = new Bitmap(path))
        {
            int w = src.Width, h = src.Height;
            Rectangle r = new Rectangle(0, 0, w, h);
            BitmapData sd = src.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            int stride = Math.Abs(sd.Stride);
            byte[] buf = new byte[stride * h];
            Marshal.Copy(sd.Scan0, buf, 0, buf.Length);
            src.UnlockBits(sd);

            int minX = int.MaxValue, minY = int.MaxValue, maxX = -1, maxY = -1;
            for (int y = 0; y < h; y++)
            {
                for (int x = 0; x < w; x++)
                {
                    if (buf[y * stride + x * 4 + 3] > alphaThreshold)
                    {
                        if (x < minX) minX = x;
                        if (x > maxX) maxX = x;
                        if (y < minY) minY = y;
                        if (y > maxY) maxY = y;
                    }
                }
            }
            if (maxX < 0) { return new int[] { 0, 0, w, h }; }
            box = new int[] { minX, minY, maxX - minX + 1, maxY - minY + 1 };

            using (Bitmap dst = new Bitmap(box[2], box[3], PixelFormat.Format32bppArgb))
            {
                // 拡大縮小をしない、まるごとの複写。画質は一切落ちない。
                BitmapData dd = dst.LockBits(new Rectangle(0, 0, box[2], box[3]),
                                             ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                int dstride = Math.Abs(dd.Stride);
                byte[] outBuf = new byte[dstride * box[3]];
                for (int y = 0; y < box[3]; y++)
                {
                    Buffer.BlockCopy(buf, (y + box[1]) * stride + box[0] * 4,
                                     outBuf, y * dstride, box[2] * 4);
                }
                Marshal.Copy(outBuf, 0, dd.Scan0, outBuf.Length);
                dst.UnlockBits(dd);
                src.Dispose();
                dst.Save(path, ImageFormat.Png);
            }
        }
        return box;
    }

    // 画像の左 xFraction の範囲を走査し、明るさが threshold を超える画素の外接矩形を返す
    // (三角形の P マークだけを切り出すために使う)
    public static int[] FindBounds(string path, double xFraction, int threshold)
    {
        using (Bitmap src = new Bitmap(path))
        {
            int w = src.Width, h = src.Height;
            int limit = (int)(w * xFraction);
            Rectangle r = new Rectangle(0, 0, w, h);
            BitmapData sd = src.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            int stride = Math.Abs(sd.Stride);
            byte[] buf = new byte[stride * h];
            Marshal.Copy(sd.Scan0, buf, 0, buf.Length);
            src.UnlockBits(sd);

            int minX = int.MaxValue, minY = int.MaxValue, maxX = -1, maxY = -1;
            for (int y = 0; y < h; y++)
            {
                for (int x = 0; x < limit; x++)
                {
                    int i = y * stride + x * 4;
                    int v = Math.Max(buf[i + 2], Math.Max(buf[i + 1], buf[i]));
                    if (v > threshold)
                    {
                        if (x < minX) minX = x;
                        if (x > maxX) maxX = x;
                        if (y < minY) minY = y;
                        if (y > maxY) maxY = y;
                    }
                }
            }
            if (maxX < 0) { return new int[] { 0, 0, 0, 0 }; }
            return new int[] { minX, minY, maxX - minX + 1, maxY - minY + 1 };
        }
    }
}
'@
Add-Type -TypeDefinition $cs -ReferencedAssemblies System.Drawing

# ---- 0. 元画像が「ロゴシート」なら、上部の横型ロゴだけを切り出す ----
# ロゴシートには、色違いの見本やモックアップ写真、日本語の説明文まで入っています。
# そのまま処理すると全部が混ざってしまうので、一番上の黒い帯(横型ロゴ)だけを取り出します。
# 判定方法: 上から1行ずつ明るさを調べ、明るい行が10行以上続いたところを黒帯の終わりとみなす。
$probe = New-Object System.Drawing.Bitmap($srcPath)
try {
    $bandEnd = $probe.Height
    $bright = 0
    for ($y = 0; $y -lt $probe.Height; $y++) {
        $sum = 0; $cnt = 0
        for ($x = 0; $x -lt $probe.Width; $x += 16) {
            $c = $probe.GetPixel($x, $y)
            $sum += [Math]::Max($c.R, [Math]::Max($c.G, $c.B)); $cnt++
        }
        if (($sum / $cnt) -gt 40) {
            $bright++
            if ($bright -ge 10) { $bandEnd = $y - 9; break }
        } else { $bright = 0 }
    }

    # 帯の下端に、シートの区切り線がうっすら残っていることがある。
    # 完全な黒に戻るまで下から削る(残すとロゴの下に横線のゴミとして出るため)。
    while ($bandEnd -gt 1) {
        $sum = 0; $cnt = 0
        for ($x = 0; $x -lt $probe.Width; $x += 16) {
            $c = $probe.GetPixel($x, $bandEnd - 1)
            $sum += [Math]::Max($c.R, [Math]::Max($c.G, $c.B)); $cnt++
        }
        if (($sum / $cnt) -gt 3) { $bandEnd-- } else { break }
    }

    if ($bandEnd -lt $probe.Height) {
        Write-Host "ロゴシートと判断しました。上部 0〜$($bandEnd-1) 行を横型ロゴとして切り出します。"
        $crop = New-Object System.Drawing.Bitmap($probe.Width, $bandEnd, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($crop)
        $g.DrawImage($probe, (New-Object System.Drawing.Rectangle(0, 0, $probe.Width, $bandEnd)),
                              0, 0, $probe.Width, $bandEnd, [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()
        $srcPath = Join-Path $env:TEMP 'primarydice-logo-band.png'
        $crop.Save($srcPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $crop.Dispose()
    }
} finally { $probe.Dispose() }

# ---- 1. 横型ロゴを透過 ----
[LogoTools]::Unpremultiply($srcPath, $logoOut)
Write-Host "透過ロゴを書き出しました: $logoOut"

# ---- 1-b. 透明なふちを切り落とす ----
# ※ここでロゴの大きさが変わります。HTML の width= height= も一緒に直してください。
$t = [LogoTools]::Trim($logoOut, 16)
$fin = New-Object System.Drawing.Bitmap($logoOut)
Write-Host ("ふちを切り落としました: 元の x={0} y={1} から {2}x{3} を切り出し" -f $t[0], $t[1], $t[2], $t[3])
Write-Host ("  → HTML には width=`"{0}`" height=`"{1}`" と書いてください" -f $fin.Width, $fin.Height)
$logoW = $fin.Width; $logoH = $fin.Height
$fin.Dispose()

# ---- 1-c. 「Creating the Future」の部分を、別の画像として切り離す ----
# サイトでは、この一行だけを後から浮かび上がらせる(フェードイン)ため、
#   logo-body.png … 標語を消したロゴ本体
#   logo-tag.png  … 標語だけ
# の2枚に分けます。logo.png(全部入り)は、SNS共有画像やヘッダー用にそのまま残します。
#
# 標語は「マークより右・ロゴ文字より下」にあるので、四角く切り取れます。
# 下の範囲は実測値です(879x200 のうち x=340〜803 / y=138〜164。余白を6pxずつ足しています)。
$tagOut  = Join-Path $outDir 'logo-tag.png'
$bodyOut = Join-Path $outDir 'logo-body.png'

$src2 = New-Object System.Drawing.Bitmap($logoOut)
try {
    # 標語の外接矩形を実測で求める(x>=250, y>=120 の範囲を走査)
    $mnX = $src2.Width; $mxX = -1; $mnY = $src2.Height; $mxY = -1
    for ($y = 120; $y -lt $src2.Height; $y++) {
        for ($x = 250; $x -lt $src2.Width; $x++) {
            if ($src2.GetPixel($x, $y).A -gt 16) {
                if ($x -lt $mnX) { $mnX = $x }; if ($x -gt $mxX) { $mxX = $x }
                if ($y -lt $mnY) { $mnY = $y }; if ($y -gt $mxY) { $mxY = $y }
            }
        }
    }
    if ($mxX -lt 0) { throw "標語(Creating the Future)の位置を検出できませんでした" }
    $pad = 6
    $rx = [Math]::Max(0, $mnX - $pad); $ry = [Math]::Max(0, $mnY - $pad)
    $rw = [Math]::Min($src2.Width  - $rx, $mxX - $mnX + 1 + $pad * 2)
    $rh = [Math]::Min($src2.Height - $ry, $mxY - $mnY + 1 + $pad * 2)
    Write-Host ("標語の範囲: x={0} y={1} w={2} h={3}" -f $rx, $ry, $rw, $rh)

    # 標語だけを切り出す
    $tag = New-Object System.Drawing.Bitmap($rw, $rh, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($tag)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.DrawImage($src2, (New-Object System.Drawing.Rectangle(0, 0, $rw, $rh)),
                 $rx, $ry, $rw, $rh, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $tag.Save($tagOut, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host ("標語を書き出しました: {0} ({1}x{2})" -f $tagOut, $rw, $rh)
    $tag.Dispose()

    # 標語を消したロゴ本体(大きさは logo.png と同じままにする。位置合わせが楽なので)
    $body = New-Object System.Drawing.Bitmap($src2.Width, $src2.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($body)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.DrawImage($src2, 0, 0)
    $g.FillRectangle([System.Drawing.Brushes]::Transparent,
                     (New-Object System.Drawing.Rectangle($rx, $ry, $rw, $rh)))
    $g.Dispose()
    $body.Save($bodyOut, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "標語を消したロゴ本体を書き出しました: $bodyOut"
    $body.Dispose()

    # CSS に書く割合(%)。画像の大きさが変わっても、この数字を差し替えれば合います。
    Write-Host ("  CSS 用: left={0:N3}%  top={1:N3}%  width={2:N3}%  height={3:N3}%" -f `
        ($rx * 100 / $src2.Width), ($ry * 100 / $src2.Height),
        ($rw * 100 / $src2.Width), ($rh * 100 / $src2.Height))
} finally { $src2.Dispose() }

# ---- 2. マーク部分(三角のP)を探す ----
# 左3分の1だけを見る。しきい値24は、圧縮ノイズの黒を拾わないための下限。
$b = [LogoTools]::FindBounds($srcPath, 0.33, 24)
if ($b[2] -le 0) { throw "マークの範囲を検出できませんでした" }
Write-Host ("マークの範囲: x={0} y={1} w={2} h={3}" -f $b[0], $b[1], $b[2], $b[3])

# ---- 3. マークだけを 512x512 に切り出して透過(mark.png) ----
# 先に縮小してから透過する。透過済み画像を縮小すると、
# 半透明部分の色が混ざって輪郭に白い縁が出ることがあるため。
$size    = 512
$padding = 0.86   # マークが正方形の中に占める割合

$src = New-Object System.Drawing.Bitmap($srcPath)
try {
    $canvas = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($canvas)
        try {
            $g.Clear([System.Drawing.Color]::Black)
            $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

            $scale = [Math]::Min(($size * $padding) / $b[2], ($size * $padding) / $b[3])
            $dw = [int]([Math]::Round($b[2] * $scale))
            $dh = [int]([Math]::Round($b[3] * $scale))
            $dx = [int](($size - $dw) / 2)
            $dy = [int](($size - $dh) / 2)

            $destRect = New-Object System.Drawing.Rectangle($dx, $dy, $dw, $dh)
            $g.DrawImage($src, $destRect, $b[0], $b[1], $b[2], $b[3], [System.Drawing.GraphicsUnit]::Pixel)
        } finally { $g.Dispose() }

        $tmp = Join-Path $env:TEMP 'primarydice-mark-black.png'
        $canvas.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
        [LogoTools]::Unpremultiply($tmp, $markOut)
        Remove-Item $tmp -Force
        Write-Host "マーク(透過)を書き出しました: $markOut"
    } finally { $canvas.Dispose() }
} finally { $src.Dispose() }

# ---- 4. 角丸の暗い四角にマークを載せてファビコンにする ----
# ブラウザのタブは 16〜32px しかない。透明背景のまま置くと線が細すぎて
# 何のアイコンか分からなくなるため、ロゴシートの「アイコン(ダーク)」と
# 同じく、角丸の暗い四角を土台にする。小さくても輪郭が残る。
$mark = New-Object System.Drawing.Bitmap($markOut)
try {
    $icon = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($icon)
        try {
            $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.Clear([System.Drawing.Color]::Transparent)

            # 角丸の四角(半径は一辺の22%。スマホのアプリアイコンに近い丸み)
            $r = [int]($size * 0.22)
            $path = New-Object System.Drawing.Drawing2D.GraphicsPath
            $path.AddArc(0, 0, $r*2, $r*2, 180, 90)
            $path.AddArc($size-$r*2, 0, $r*2, $r*2, 270, 90)
            $path.AddArc($size-$r*2, $size-$r*2, $r*2, $r*2, 0, 90)
            $path.AddArc(0, $size-$r*2, $r*2, $r*2, 90, 90)
            $path.CloseFigure()

            $fill = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#1A1A1A'))
            $g.FillPath($fill, $path)
            $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#2E2E2E'), 3)
            $g.DrawPath($pen, $path)
            $fill.Dispose(); $pen.Dispose(); $path.Dispose()

            # マークを中央に。四角の 62% くらいが収まりが良い
            $mw = [int]($size * 0.62)
            $mh = [int]($mark.Height * $mw / $mark.Width)
            $g.DrawImage($mark, [int](($size-$mw)/2), [int](($size-$mh)/2), $mw, $mh)
        } finally { $g.Dispose() }
        $icon.Save($iconOut, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host "ファビコンを書き出しました: $iconOut"
    } finally { $icon.Dispose() }
} finally { $mark.Dispose() }

# ---- 5. SNS共有用の画像(OGP画像)を作る ----
# LINE や X などにURLを貼ると、四角い画像つきのカードが表示されます。
# そこに使う画像です。透過ロゴのまま渡すと、相手のアプリが白背景で表示したときに
# 銀色のロゴが見えなくなるので、背景を塗った専用の画像を用意します。
# 大きさ 1200×630 は、各サービス共通のおすすめサイズです。
$ogOut = Join-Path $outDir 'og.png'
$logo = New-Object System.Drawing.Bitmap($logoOut)
try {
    $og = New-Object System.Drawing.Bitmap(1200, 630, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($og)
        try {
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.ColorTranslator]::FromHtml('#121212'))

            # 上下に細い銀の線を1本ずつ(サイトの雰囲気に合わせる)
            $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#2A2A2A'), 2)
            $g.DrawLine($pen, 0, 3, 1200, 3)
            $g.DrawLine($pen, 0, 627, 1200, 627)
            $pen.Dispose()

            $lw = 780
            $lh = [int]($logo.Height * $lw / $logo.Width)
            $g.DrawImage($logo, [int]((1200-$lw)/2), [int]((630-$lh)/2), $lw, $lh)
        } finally { $g.Dispose() }
        $og.Save($ogOut, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host "SNS共有用の画像を書き出しました: $ogOut"
    } finally { $og.Dispose() }
} finally { $logo.Dispose() }


# 注: 明るい背景で使う「単色ロゴ」は作りません。
# このロゴは立体的な陰影で形が出来ているため、色を1色に潰すと
# 暗い面が抜け落ちて形が壊れます(不透明度の約半分が 0〜31 に集中しているため)。
# 紙のような明るい面では、ロゴ画像ではなく favicon.png(黒い角丸アイコン)と
# 文字組みの社名を使ってください。ロゴシートでも明るい面には
# 「アイコン(ライト)」しか使われていません。

Write-Host ""
Write-Host "完了。assets\ の中身を目で見て確認してください。"
