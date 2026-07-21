# Build lab flat flat config.plist from active_profile.json
# Deploy to: /var/jb/etc/ipfaker/config.plist  (like ipfaker/config.plist)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$src = Join-Path $Root "config\active_profile.json"
$out = Join-Path $Root "config\config.plist"

$j = Get-Content $src -Raw -Encoding UTF8 | ConvertFrom-Json

function S($o, $a) {
  if ($null -eq $o) { return "" }
  if ($o.PSObject.Properties.Name -contains $a) {
    $v = $o.$a
    if ($null -eq $v) { return "" }
    return [string]$v
  }
  return ""
}

$productType = S $j.model "ProductType"
if (-not $productType) { $productType = S $j.hooks.mobilegestalt "ProductType" }
$marketing = S $j.model "MarketingName"
if (-not $marketing) { $marketing = S $j.model "ProductName" }
if (-not $marketing) { $marketing = "iPhone 15 Pro" }

$hw = S $j.model "HWModelStr"
if (-not $hw) { $hw = S $j.model "HardwareModel" }

$pairs = @(
  @("Enabled", "true"),
  @("ProductType", $productType),
  @("MarketingName", $marketing),
  @("DeviceName", (S $j.model "DeviceName")),
  @("UserAssignedDeviceName", (S $j.model "UserAssignedDeviceName")),
  @("HWModelStr", $hw),
  @("HardwareModel", $hw),
  @("ModelNumber", (S $j.model "ModelNumber")),
  @("RegionInfo", (S $j.model "RegionInfo")),
  @("RegionCode", (S $j.model "RegionCode")),
  @("RegulatoryModelNumber", (S $j.model "RegulatoryModelNumber")),
  @("HardwarePlatform", (S $j.model "HardwarePlatform")),
  @("CPUArchitecture", (S $j.model "CPUArchitecture")),
  @("DeviceClass", "iPhone"),
  @("SerialNumber", (S $j.identity "SerialNumber")),
  @("UniqueDeviceID", (S $j.identity "UniqueDeviceID")),
  @("UniqueChipID", (S $j.identity "UniqueChipID")),
  @("ProductVersion", (S $j.os "ProductVersion")),
  @("BuildVersion", (S $j.os "BuildVersion")),
  @("ProductBuildVersion", (S $j.os "BuildVersion")),
  @("IDFA", (S $j.identity "IDFA")),
  @("IDFV", (S $j.identity "IDFV")),
  @("identifierForVendor", (S $j.identity "IDFV")),
  @("InternationalMobileEquipmentIdentity", (S $j.identity "IMEI")),
  @("InternationalMobileEquipmentIdentity2", (S $j.identity "IMEI2")),
  @("MobileEquipmentIdentifier", (S $j.identity "MEID")),
  @("WifiAddress", (S $j.network "WifiAddress")),
  @("BluetoothAddress", (S $j.network "BluetoothAddress")),
  @("EthernetMacAddress", (S $j.network "EthernetMacAddress")),
  @("carrierName", (S $j.telephony "CarrierName")),
  @("carrierMCC", (S $j.telephony "MobileCountryCode")),
  @("carrierMNC", (S $j.telephony "MobileNetworkCode")),
  @("carrierISO", (S $j.telephony "ISOCountryCode")),
  @("carrierRadioAccess", (S $j.telephony "CurrentRadioAccessTechnology")),
  @("CarrierName", (S $j.telephony "CarrierName")),
  @("MobileCountryCode", (S $j.telephony "MobileCountryCode")),
  @("MobileNetworkCode", (S $j.telephony "MobileNetworkCode")),
  @("ISOCountryCode", (S $j.telephony "ISOCountryCode")),
  @("main-screen-width", (S $j.display "NativeWidth")),
  @("main-screen-height", (S $j.display "NativeHeight")),
  @("main-screen-scale", (S $j.display "ScreenScale")),
  @("main-screen-pitch", (S $j.display "main-screen-pitch"))
)

function Esc([string]$s) {
  if ($null -eq $s) { return "" }
  return ($s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;')
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine('<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">')
[void]$sb.AppendLine('<plist version="1.0">')
[void]$sb.AppendLine('<dict>')
foreach ($p in $pairs) {
  $k = $p[0]; $v = $p[1]
  [void]$sb.AppendLine("  <key>$(Esc $k)</key>")
  if ($v -eq "true") {
    [void]$sb.AppendLine('  <true/>')
  } elseif ($v -match '^\d+$' -and $k -match 'screen|pitch|scale|width|height') {
    [void]$sb.AppendLine("  <integer>$v</integer>")
  } else {
    [void]$sb.AppendLine("  <string>$(Esc $v)</string>")
  }
}
[void]$sb.AppendLine('</dict>')
[void]$sb.AppendLine('</plist>')

[System.IO.File]::WriteAllText($out, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host "[iPFaker] lab flat config.plist -> $out"
Write-Host "  ProductType=$productType MarketingName=$marketing"
