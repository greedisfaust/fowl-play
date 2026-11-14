$p = 'C:/Users/Faust/Desktop/fowl-play/dev-fowl-play/player/player.gd'
$c = [System.IO.File]::ReadAllText($p)
$old = 'var _punch_charge_auto_fired: bool = false   # true once charged punch auto-fired at 1s'
$new = $old + [Environment]::NewLine + 'var _head_rest_y: float = 1.6   # owner'"'"'s eye height when standing' + [Environment]::NewLine + 'var _body_rest_transform: Transform3D = Transform3D.IDENTITY   # $Body rest transform'
if ($c -match [regex]::Escape($old)) { $c = $c -replace [regex]::Escape($old), $new; [System.IO.File]::WriteAllText($p, $c, (New-Object System.Text.UTF8Encoding $false)); "replaced" } else { "NOT FOUND" }
