#requires -Version 7.4
<# Convert the transparent PNG master to a README preview and multi-size Windows ICO. #>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$master=Join-Path $ProjectRoot 'assets/lokiente-logo.png'
$iconPath=Join-Path $ProjectRoot 'Quellpaket/assets/lokiente.ico'
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($iconPath))
$source=[Drawing.Image]::FromFile($master)
function Convert-LogoPng([int]$Size) {
    $bitmap=[Drawing.Bitmap]::new($Size,$Size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    $stream=[IO.MemoryStream]::new()
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.CompositingMode=[Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $scale=[Math]::Min($Size/$source.Width,$Size/$source.Height)
        $width=[int][Math]::Round($source.Width*$scale);$height=[int][Math]::Round($source.Height*$scale)
        $graphics.DrawImage($source,[Drawing.Rectangle]::new([int](($Size-$width)/2),[int](($Size-$height)/2),$width,$height))
        $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
        return ,$stream.ToArray()
    } finally {$graphics.Dispose();$bitmap.Dispose();$stream.Dispose()}
}
try {
    [IO.File]::WriteAllBytes((Join-Path $ProjectRoot 'assets/lokiente-preview.png'),(Convert-LogoPng 512))
    $sizes=@(16,24,32,48,64,128,256)
    $frames=@(foreach($size in $sizes){[pscustomobject]@{Size=$size;Bytes=(Convert-LogoPng $size)}})
    $output=[IO.MemoryStream]::new();$writer=[IO.BinaryWriter]::new($output)
    try {
        $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$frames.Count)
        $offset=6+16*$frames.Count
        foreach($frame in $frames){
            $dimension=if($frame.Size -eq 256){0}else{$frame.Size}
            $writer.Write([byte]$dimension);$writer.Write([byte]$dimension)
            $writer.Write([byte]0);$writer.Write([byte]0)
            $writer.Write([uint16]1);$writer.Write([uint16]32)
            $writer.Write([uint32]$frame.Bytes.Length);$writer.Write([uint32]$offset)
            $offset+=$frame.Bytes.Length
        }
        foreach($frame in $frames){$writer.Write([byte[]]$frame.Bytes)}
        $writer.Flush();[IO.File]::WriteAllBytes($iconPath,$output.ToArray())
    } finally {$writer.Dispose();$output.Dispose()}
    Write-Output "LoKiEnte: PNG preview 512px; ICO sizes $($sizes -join ', ')px."
} finally {$source.Dispose()}
