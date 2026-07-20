# Build HIOS-style flat config.plist from active_profile.json
# Output: config/config.plist  -> deploy to /var/jb/etc/ipfaker/config.plist
# Matches ChangeInfoIos keys: ProductType, MarketingName, SerialNumber, carrier*, etc.

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$src = Join-Path $Root "config\active_profile.json"
$out = Join-Path $Root "config\config.plist"

$j = Get-Content $src -Raw -Encoding UTF8 | ConvertFrom-Json

function S($o, $a, $b = $null, $c = $null) {
  if ($null -eq $o) { return $null }
  $v = $o
  foreach ($k in @($a, $b, $c)) {
    if ($null -eq $k) { break }
    if ($v.PSObject.Properties.Name -contains $k) { $v = $v.$k } else { return $null }
  }
  return $v
}

$productType = S $j.model "ProductType"
if (-not $productType) { $productType = S $j.hooks.mobilegestalt "ProductType" }
$marketing = S $j.model "MarketingName"
if (-not $marketing) { $marketing = S $j.model "ProductName" }
if (-not $marketing) { $marketing = "iPhone 15 Pro" }

# Flat dict HIOS-style
$flat = [ordered]@{
  Enabled                     = $true
  ProductType                 = "$productType"
  MarketingName               = "$marketing"
  DeviceName                  = "$(S $j.model 'DeviceName')"
  UserAssignedDeviceName      = "$(S $j.model 'UserAssignedDeviceName')"
  HWModelStr                  = "$(S $j.model 'HWModelStr')"
  HardwareModel               = "$(S $j.model 'HardwareModel')"
  ModelNumber                 = "$(S $j.model 'ModelNumber')"
  RegionInfo                  = "$(S $j.model 'RegionInfo')"
  RegionCode                  = "$(S $j.model 'RegionCode')"
  RegulatoryModelNumber       = "$(S $j.model 'RegulatoryModelNumber')"
  HardwarePlatform            = "$(S $j.model 'HardwarePlatform')"
  CPUArchitecture             = "$(S $j.model 'CPUArchitecture')"
  DeviceClass                 = "iPhone"
  SerialNumber                = "$(S $j.identity 'SerialNumber')"
  UniqueDeviceID              = "$(S $j.identity 'UniqueDeviceID')"
  UniqueChipID                = "$(S $j.identity 'UniqueChipID')"
  ProductVersion              = "$(S $j.os 'ProductVersion')"
  BuildVersion                = "$(S $j.os 'BuildVersion')"
  ProductBuildVersion         = "$(S $j.os 'BuildVersion')"
  IDFA                        = "$(S $j.identity 'IDFA')"
  IDFV                        = "$(S $j.identity 'IDFV')"
  identifierForVendor         = "$(S $j.identity 'IDFV')"
  InternationalMobileEquipmentIdentity  = "$(S $j.identity 'IMEI')"
  InternationalMobileEquipmentIdentity2 = "$(S $j.identity 'IMEI2')"
  MobileEquipmentIdentifier   = "$(S $j.identity 'MEID')"
  WifiAddress                 = "$(S $j.network 'WifiAddress')"
  BluetoothAddress            = "$(S $j.network 'BluetoothAddress')"
  EthernetMacAddress          = "$(S $j.network 'EthernetMacAddress')"
  carrierName                 = "$(S $j.telephony 'CarrierName')"
  carrierMCC                  = "$(S $j.telephony 'MobileCountryCode')"
  carrierMNC                  = "$(S $j.telephony 'MobileNetworkCode')"
  carrierISO                  = "$(S $j.telephony 'ISOCountryCode')"
  carrierRadioAccess          = "$(S $j.telephony 'CurrentRadioAccessTechnology')"
  CarrierName                 = "$(S $j.telephony 'CarrierName')"
  MobileCountryCode           = "$(S $j.telephony 'MobileCountryCode')"
  MobileNetworkCode           = "$(S $j.telephony 'MobileNetworkCode')"
  ISOCountryCode              = "$(S $j.telephony 'ISOCountryCode')"
  AllowsVOIP                  = $true
  main-screen-width           = [int](S $j.display 'NativeWidth')
  main-screen-height          = [int](S $j.display 'NativeHeight')
  main-screen-scale           = [int](S $j.display 'ScreenScale')
  main-screen-pitch           = [int](S $j.display 'main-screen-pitch')
}

# Build XML plist manually (reliable on Windows without plutil)
function Esc([string]$s) {
  if ($null -eq $s) { return "" }
  return ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;')
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine('<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">')
[void]$sb.AppendLine('<plist version="1.0">')
[void]$sb.AppendLine('<dict>')
foreach ($k in $flat.Keys) {
  $v = $flat[$k]
  [void]$sb.AppendLine("  <key>$(Esc $k)</key>")
  if ($v -is [bool]) {
    if ($v) { [void]$sb.AppendLine('  <true/>') } else { [void]$sb.AppendLine('  <false/>') }
  } elseif ($v -is [int] -or $v -is [long]) {
    [void]$sb.AppendLine("  <integer>$v</integer>")
  } else {
    [void]$sb.AppendLine("  <string>$(Esc ([string]$v))</string>")
  }
}
[void]$sb.AppendLine('</dict>')
[void]$sb.AppendLine('</plist>')

[System.IO.File]::WriteAllText($out, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host "[iPFaker] HIOS-style config.plist -> $out"
Write-Host "  ProductType=$productType MarketingName=$marketing Serial=$($flat.SerialNumber)"
