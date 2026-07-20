# iPFaker — rebuild active_profile.json (Fake Nông + Fake Sâu merged)
# Usage: powershell -File scripts\build_active_profile.ps1

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$srcPath = Join-Path $Root "config\device_profile.json"
$outPath = Join-Path $Root "config\active_profile.json"

Write-Host "[iPFaker] Building full active profile (Nông + Sâu)..."
Write-Host "  Source: $srcPath"

$src = Get-Content $srcPath -Raw -Encoding UTF8 | ConvertFrom-Json

function ConvertTo-PlainObject($obj) {
  if ($null -eq $obj) { return $null }
  if ($obj -is [string] -or $obj -is [int] -or $obj -is [long] -or $obj -is [double] -or $obj -is [decimal] -or $obj -is [bool]) {
    return $obj
  }
  # PSCustomObject from ConvertFrom-Json
  if ($obj -is [System.Management.Automation.PSCustomObject]) {
    $h = [ordered]@{}
    foreach ($p in $obj.PSObject.Properties) {
      if ($p.Name -eq '_fake_level' -or $p.Name -eq 'comment') { continue }
      $h[$p.Name] = ConvertTo-PlainObject $p.Value
    }
    return $h
  }
  # Array / list — always keep as array (even 1 element)
  if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string]) -and -not ($obj -is [System.Collections.IDictionary])) {
    $arr = [System.Collections.Generic.List[object]]::new()
    foreach ($i in $obj) { $arr.Add((ConvertTo-PlainObject $i)) }
    return , $arr.ToArray()
  }
  # Hashtable / ordered
  if ($obj -is [System.Collections.IDictionary]) {
    $h = [ordered]@{}
    foreach ($k in $obj.Keys) {
      if ($k -eq '_fake_level' -or $k -eq 'comment') { continue }
      $h[$k] = ConvertTo-PlainObject $obj[$k]
    }
    return $h
  }
  return $obj
}

function Get-Section($name) {
  if ($src.PSObject.Properties.Name -contains $name) {
    return ConvertTo-PlainObject $src.$name
  }
  return [ordered]@{}
}

function Merge-Ordered([object[]]$maps) {
  $out = [ordered]@{}
  foreach ($m in $maps) {
    if ($null -eq $m) { continue }
    if ($m -is [System.Collections.IDictionary]) {
      foreach ($k in $m.Keys) { $out[$k] = $m[$k] }
    } elseif ($m -is [System.Management.Automation.PSCustomObject]) {
      foreach ($p in $m.PSObject.Properties) { $out[$p.Name] = $p.Value }
    }
  }
  return $out
}

# Canonical section names in active_profile (source may use uiddevice typo)
$sectionAlias = @{
  'uiddevice' = 'uidevice'
}

$nongNames = @($src.fake_level_index.nong_sections)
$sauNames  = @($src.fake_level_index.sau_sections)
$allNames  = @($nongNames + $sauNames | Select-Object -Unique)

$sections = [ordered]@{}
foreach ($name in $allNames) {
  $canonical = if ($sectionAlias.ContainsKey($name)) { $sectionAlias[$name] } else { $name }
  $sections[$canonical] = Get-Section $name
  # also keep raw name lookup if different
  if ($canonical -ne $name) {
    if (-not $sections.Contains($name)) {
      # already stored under canonical
    }
  }
}

$mg = Merge-Ordered @(
  $sections.mobilegestalt_map,
  $sections.mobilegestalt_map_deep,
  $sections.mobilegestalt_capabilities
)
if ($sections.identity -and ($sections.identity -is [System.Collections.IDictionary])) {
  if ($sections.identity.Contains('UDID')) { $mg['UniqueDeviceID'] = $sections.identity['UDID'] }
  if ($sections.identity.Contains('SerialNumber')) { $mg['SerialNumber'] = $sections.identity['SerialNumber'] }
  if ($sections.identity.Contains('IMEI')) { $mg['InternationalMobileEquipmentIdentity'] = $sections.identity['IMEI'] }
  if ($sections.identity.Contains('IMEI2')) { $mg['InternationalMobileEquipmentIdentity2'] = $sections.identity['IMEI2'] }
  if ($sections.identity.Contains('MEID')) { $mg['MobileEquipmentIdentifier'] = $sections.identity['MEID'] }
}
if ($sections.identity_deep -and ($sections.identity_deep -is [System.Collections.IDictionary])) {
  foreach ($k in @('UniqueChipID', 'DieID', 'ApECID')) {
    if ($sections.identity_deep.Contains($k)) { $mg[$k] = $sections.identity_deep[$k] }
  }
}

$sys = Merge-Ordered @($sections.sysctl_map, $sections.sysctl_deep)
$identityFull = Merge-Ordered @($sections.identity, $sections.identity_deep, $sections.secure_element)
$telephonyFull = Merge-Ordered @($sections.telephony, $sections.esim_sim, $sections.telephony_deep)
$displayFull = Merge-Ordered @($sections.display, $sections.display_deep)
$networkFull = Merge-Ordered @($sections.network, $sections.network_deep)
$storageFull = Merge-Ordered @($sections.storage, $sections.volume_disk_deep)

# Prefer canonical uidevice; fall back to raw uiddevice from source
$uideviceSec = $null
if ($sections.Contains('uidevice') -and $null -ne $sections['uidevice'] -and @($sections['uidevice'].Keys).Count -gt 0) {
  $uideviceSec = $sections['uidevice']
} else {
  $uideviceSec = Get-Section 'uiddevice'
}

$active = [ordered]@{
  _meta = [ordered]@{
    profile_id            = "iphone15pro-vn-full-active"
    version               = "2.1.1"
    generated_from        = "device_profile.json"
    apply_mode            = "full"
    fake_nong             = $true
    fake_sau              = $true
    one_button            = $true
    target_bundle_id      = "com.zing.zalo"
    identity_note         = "SYNTHETIC lab profile only. Full Nông+Sâu merged for single apply."
    section_count         = $allNames.Count
    sections_applied      = @($allNames)
    generated_at_utc      = (Get-Date).ToUniversalTime().ToString("o")
  }
  apply = [ordered]@{
    enabled                    = $true
    mode                       = "full"
    button_action              = "apply_full_nong_and_sau"
    apply_nong                 = $true
    apply_sau                  = $true
    apply_order                = @("nong_first", "sau_override")
    kill_zalo_after_apply      = $true
    wipe_zalo_storage_on_apply = $true
    modules_all                = $true
  }
  identity         = $identityFull
  model            = $sections.model
  hardware         = $sections.hardware
  os               = $sections.os
  display          = $displayFull
  network          = $networkFull
  telephony        = $telephonyFull
  locale           = $sections.locale
  storage          = $storageFull
  battery          = $sections.battery
  uidevice         = $uideviceSec
  metal_gpu        = $sections.metal_gpu
  camera_sensors   = $sections.camera_sensors
  biometry         = $sections.biometry
  boot_time        = $sections.boot_time
  webview          = $sections.webview
  sdk_attribution  = $sections.sdk_attribution
  zalo_storage     = $sections.zalo_storage
  jailbreak_hide   = $sections.jailbreak_hide
  process_env      = $sections.process_env
  flags = [ordered]@{
    IsPhysicalDevice           = $true
    IsSimulator                = $false
    IsJailbrokenSpoof          = $false
    AdvertisingTrackingEnabled = $true
    LimitAdTracking            = $false
    FakeLevelDefault           = "full"
    ApplyNong                  = $true
    ApplySau                   = $true
    OneButtonFullFake          = $true
  }
  hooks = [ordered]@{
    mobilegestalt = $mg
    sysctl        = $sys
  }
}

function ConvertTo-JsonSafe($o, [int]$depth = 0) {
  if ($depth -gt 40) { return $null }
  if ($null -eq $o) { return $null }
  if ($o -is [bool]) { return $o }
  if ($o -is [int] -or $o -is [long] -or $o -is [double] -or $o -is [decimal]) { return $o }
  if ($o -is [string]) { return $o }
  if ($o -is [System.Collections.IDictionary] -or ($o.GetType().Name -match 'OrderedDictionary|Hashtable')) {
    $ht = [ordered]@{}
    foreach ($k in $o.Keys) { $ht[$k] = (ConvertTo-JsonSafe $o[$k] ($depth + 1)) }
    return [pscustomobject]$ht
  }
  if ($o -is [System.Array] -or ($o -is [System.Collections.IEnumerable] -and -not ($o -is [string]))) {
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($i in $o) { $list.Add((ConvertTo-JsonSafe $i ($depth + 1))) }
    # Force array serialization even for single element
    return , $list.ToArray()
  }
  if ($o -is [System.Management.Automation.PSCustomObject]) {
    $ht = [ordered]@{}
    foreach ($p in $o.PSObject.Properties) { $ht[$p.Name] = (ConvertTo-JsonSafe $p.Value ($depth + 1)) }
    return [pscustomobject]$ht
  }
  return $o
}

# Manual JSON via Newtonsoft-less path: use ConvertTo-Json with depth
# and post-fix known single-element array collapses if needed
$psObj = ConvertTo-JsonSafe $active
$json = $psObj | ConvertTo-Json -Depth 40 -Compress:$false

# Ensure UTF-8 no BOM
[System.IO.File]::WriteAllText($outPath, $json, [System.Text.UTF8Encoding]::new($false))

# Quick verify
$verify = Get-Content $outPath -Raw -Encoding UTF8 | ConvertFrom-Json
$uidOk = $null -ne $verify.uidevice -and $null -ne $verify.uidevice.name
$mgCount = @($verify.hooks.mobilegestalt.PSObject.Properties).Count
$sysCount = @($verify.hooks.sysctl.PSObject.Properties).Count

Write-Host "[iPFaker] OK -> $outPath"
Write-Host "  Sections : $($allNames.Count)"
Write-Host "  MG keys  : $mgCount"
Write-Host "  Sysctl   : $sysCount"
Write-Host "  uidevice : $(if ($uidOk) { 'OK (' + $verify.uidevice.name + ')' } else { 'MISSING' })"
Write-Host "  Mode     : full (Nông + Sâu, one button)"
if (-not $uidOk) { Write-Warning "uidevice section is null - check device_profile.uiddevice" }
