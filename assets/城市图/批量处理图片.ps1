# ============================================================================
# 小满出行 · 城市配图批量处理脚本
# ----------------------------------------------------------------------------
# 作用：把「原图」文件夹里的照片，自动处理成卡片能用的规格，并按城市名
#       放进 assets\城市图\ 目录。
#
# 用法：
#   1. 把你下载的原图（不管什么文件名）全部丢进 assets\城市图\原图\ 文件夹
#   2. 每张图重命名为城市名（例如 大理.jpg、丽江.jpg），扩展名保持原样
#   3. 右键本文件 → 「使用 PowerShell 运行」
#
# 脚本会做三件事：居中裁切成 3:2 → 缩放到宽 900px → 存成 JPG（质量 85）
# 需要 Windows 自带的 .NET 图像库，无需安装任何软件。
# ============================================================================

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# 路径：脚本放在 assets\城市图\ 下，所以用脚本自身位置推算
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcDir    = Join-Path $scriptDir '原图'
$outDir    = $scriptDir

if (-not (Test-Path -LiteralPath $srcDir)) {
    New-Item -ItemType Directory -Path $srcDir | Out-Null
    Write-Host "已创建原图文件夹：$srcDir" -ForegroundColor Yellow
    Write-Host "请把下载好的照片放进去（重命名为城市名），然后重新运行本脚本。" -ForegroundColor Yellow
    exit
}

$files = Get-ChildItem -LiteralPath $srcDir -File |
         Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|webp|bmp)$' }

if ($files.Count -eq 0) {
    Write-Host "原图文件夹里没有找到图片：$srcDir" -ForegroundColor Yellow
    exit
}

Write-Host "找到 $($files.Count) 张原图，开始处理……" -ForegroundColor Cyan

# 卡片图位约为 340×134（约 2.5:1），但留出余量用 3:2 裁切，
# 卡片显示时由 CSS 的 background-size:cover 再裁一次，主体不会丢。
$targetRatio = 3.0 / 2.0
$targetWidth = 900

$ok = 0; $fail = 0
foreach ($f in $files) {
    $city = $f.BaseName
    try {
        $img = [System.Drawing.Image]::FromFile($f.FullName)

        # 1) 居中裁切成目标比例
        $w = $img.Width; $h = $img.Height
        $ratio = $w / $h
        if ($ratio -gt $targetRatio) {
            # 太宽：裁掉左右
            $newW = [int]($h * $targetRatio)
            $srcRect = New-Object System.Drawing.Rectangle ([int](($w - $newW) / 2)), 0, $newW, $h
        } else {
            # 太高：裁掉上下
            $newH = [int]($w / $targetRatio)
            $srcRect = New-Object System.Drawing.Rectangle 0, ([int](($h - $newH) / 2)), $w, $newH
        }

        # 2) 缩放到目标宽度
        $outH = [int]($targetWidth * $srcRect.Height / $srcRect.Width)
        $bmp = New-Object System.Drawing.Bitmap $targetWidth, $outH
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $destRect = New-Object System.Drawing.Rectangle 0, 0, $targetWidth, $outH
        $g.DrawImage($img, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()

        # 3) 存成 JPG（质量 85）
        $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
                   Where-Object { $_.MimeType -eq 'image/jpeg' }
        $params = New-Object System.Drawing.Imaging.EncoderParameters 1
        $params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
            [System.Drawing.Imaging.Encoder]::Quality, [long]85)

        $outPath = Join-Path $outDir ($city + '.jpg')
        $bmp.Save($outPath, $encoder, $params)

        $params.Dispose(); $bmp.Dispose(); $img.Dispose()

        $kb = [int]((Get-Item -LiteralPath $outPath).Length / 1KB)
        Write-Host ("  ✓ {0} → {1}.jpg  （{2}×{3}，{4} KB）" -f $f.Name, $city, $targetWidth, $outH, $kb) -ForegroundColor Green
        $ok++
    }
    catch {
        Write-Host ("  ✗ {0} 处理失败：{1}" -f $f.Name, $_.Exception.Message) -ForegroundColor Red
        $fail++
    }
}

Write-Host ""
Write-Host "完成：成功 $ok 张，失败 $fail 张。" -ForegroundColor Cyan
Write-Host "处理后的图片已放在：$outDir" -ForegroundColor Cyan
Write-Host "刷新 小满出行.html 就能看到卡片上的实景图。" -ForegroundColor Cyan
Write-Host ""
Write-Host "注意：文件名必须是纯城市名，且要和卡片上的名字完全一致，例如：" -ForegroundColor Yellow
Write-Host "      北京.jpg / 上海.jpg / 杭州.jpg / 苏州.jpg / 成都.jpg / 西双版纳.jpg" -ForegroundColor Yellow
Write-Host "      丽江.jpg / 大理.jpg / 三亚.jpg / 厦门.jpg / 青岛.jpg / 昆明.jpg" -ForegroundColor Yellow
Write-Host "      贵阳.jpg / 桂林.jpg / 西安.jpg / 珠海.jpg / 大连.jpg / 鼓浪屿.jpg" -ForegroundColor Yellow
