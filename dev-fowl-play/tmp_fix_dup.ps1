$p = 'C:/Users/Faust/Desktop/fowl-play/dev-fowl-play/player/player.gd'
$c = [System.IO.File]::ReadAllText($p)
$lines = $c -split "`n"
$out = [System.Collections.Generic.List[string]]::new()
$i = 0
while ($i -lt $lines.Count) {
    if ($lines[$i] -match '_body_rest_transform = \$Body.transform' -and $i + 5 -lt $lines.Count -and $lines[$i+1] -match 'add_child\(overlay\)' -and $lines[$i+5] -match '# Wire up components') {
        $out.Add($lines[$i])
        $out.Add($lines[$i+5])
        $i = $i + 6
    } else {
        $out.Add($lines[$i])
        $i++
    }
}
[System.IO.File]::WriteAllText($p, ($out -join "`n"), (New-Object System.Text.UTF8Encoding $false))
"done"
