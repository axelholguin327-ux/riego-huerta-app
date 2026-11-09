# Genera las capturas del prototipo y de los wireframes con Microsoft Edge (headless).
# Uso:  powershell -ExecutionPolicy Bypass -File design\capturar.ps1
$ErrorActionPreference = 'Continue'  # Edge escribe avisos inofensivos en stderr
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$proto = Join-Path $root 'prototipo\index.html'
$url = 'file:///' + ($proto -replace '\\', '/')
$profile = Join-Path $env:TEMP 'edge-capturas-huerta'

$pantallas = [ordered]@{
  '01_login'            = 'login'
  '02_login_validacion' = 'login/error'
  '03_panel_general'    = 'panel'
  '04_detalle_zona'     = 'zona/2'
  '05_control_riego'    = 'riego'
  '06_confirmar_riego'  = 'riego/dialogo'
  '07_alarmas'          = 'alarmas'
  '08_historial'        = 'historial'
  '09_mas_opciones'     = 'mas'
  '10_tarjetas_rfid'    = 'rfid'
  '11_registrar_tarjeta'= 'rfid-nueva/leida'
  '12_dispositivo'      = 'dispositivo'
  '13_cerrar_sesion'    = 'mas/salir'
}

function Capturar($modo, $carpeta, $nombres) {
  $dest = Join-Path $root $carpeta
  New-Item -ItemType Directory -Force $dest | Out-Null
  foreach ($k in $nombres) {
    $q = if ($modo) { "?captura&modo=$modo" } else { '?captura' }
    $png = Join-Path $dest "$k.png"
    & $edge --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 `
      --window-size=390,844 --virtual-time-budget=4000 --user-data-dir="$profile" `
      --screenshot="$png" "$url$q#$($pantallas[$k])" 2>$null | Out-Null
    Write-Host "  $carpeta\$k.png"
  }
}

Write-Host 'Prototipo:'
Capturar '' 'capturas-prototipo' $pantallas.Keys
Write-Host 'Wireframes:'
Capturar 'wireframe' 'wireframes' @('01_login','03_panel_general','04_detalle_zona','05_control_riego','07_alarmas','08_historial','09_mas_opciones','10_tarjetas_rfid','11_registrar_tarjeta')
