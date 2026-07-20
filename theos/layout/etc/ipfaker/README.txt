iPFaker config (rootless)
=========================
Deploy from Windows:
  injector\deploy.ps1 -DeviceHost <IP> -Layout roothide -RebuildProfile

Expected files:
  active_profile.json   (merged Nông + Sâu)
  device_profile.json
  main.plist
  apply.json

Runtime also checks:
  /var/mobile/Library/iPFaker/active_profile.json  (RootHide-friendly)
