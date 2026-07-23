# iPFaker split stack: MG (spoof+Extra) + CT (telephony+Deep) + JB (hide expand)
# Link libsubstrate.dylib (ElleKit), NOT CydiaSubstrate.framework (missing on Dopamine)

export TARGET := iphone:clang:latest:14.0
# Dual-arch: arm64 (A9–A11 e.g. iPhone 7) + arm64e (A12+ lab XS Max).
# Fat + proper ldid/trustcache on install (postinst). Thin arm64e-only broke new A10/A11 devices.
export ARCHS := arm64 arm64e
export THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

# Split stack (Dopamine AMFI):
#   MG = spoof + Extra core (screen/disk/UA/getifaddrs/access-stat) — third-party + Safari lab
#   About = tiny MG-only for Settings → About (platform Preferences rejects large MG)
#   CT = telephony + deep rewrite
#   JB = expanded hide (fopen/getenv/fileExists) — optional, fails independently
# AA = ServerLite (AppAttest/Proxy/WebRTC) — loads first alphabetically, tiny, no IPFConfig.m
TWEAK_NAME = iPFakerAA iPFakerAbout iPFakerAboutID iPFakerAboutUI iPFakerAboutVer iPFakerMG iPFakerCT iPFakerJB

# MG = spoof + Extra (screen/disk/UA/getifaddrs/access-stat/WKWebView)
# fishhook.c OFF by default: keeps MG ~123k AMFI-safe. ElleKit MSHook is primary on Dopamine.
# Optional: add src/fishhook.c + -DIPF_FISHHOOK_FALLBACK=1 only if MSHook is unavailable.
# AA: server mitigations lite (AppAttest/Proxy/WebRTC) — own dylib, no CFNetwork, no IPFConfig.m
iPFakerAA_FILES = src/IPFHooksServerLite.m
iPFakerAA_CFLAGS = -fobjc-arc -Os -fvisibility=hidden -Wno-unused-variable -Wno-unused-function -I$(THEOS_PROJECT_DIR)/src
iPFakerAA_FRAMEWORKS = Foundation
iPFakerAA_LIBRARIES = substrate
iPFakerAA_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerAA.dylib -Wl,-dead_strip

# About: Config + MG hooks (model# / marketing / MG ProductVersion)
iPFakerAbout_FILES = TweakAbout.x src/IPFConfig.m src/IPFHooksMG.m
iPFakerAbout_CFLAGS = -fobjc-arc -Os -fvisibility=hidden -DIPF_NO_MG_DEBUG=1 -DIPF_ABOUT_LITE=1 -ffunction-sections -fdata-sections -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerAbout_FRAMEWORKS = UIKit Foundation AdSupport
iPFakerAbout_LIBRARIES = substrate
iPFakerAbout_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerAbout.dylib -Wl,-dead_strip -Wl,-x

# AboutVer: SystemVersion/MG version keys. No IPFConfig.m — stays AMFI-lean.
iPFakerAboutVer_FILES = TweakAboutVer.x
iPFakerAboutVer_CFLAGS = -fobjc-arc -Os -fvisibility=hidden -ffunction-sections -fdata-sections -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations
iPFakerAboutVer_FRAMEWORKS = Foundation UIKit
iPFakerAboutVer_LIBRARIES = substrate
iPFakerAboutVer_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerAboutVer.dylib -Wl,-dead_strip -Wl,-x

# AboutID: tiny wash for Settings Tên / Số máy / Số sê-ri (kept lean for Preferences inject)
iPFakerAboutID_FILES = TweakAboutID.x
iPFakerAboutID_CFLAGS = -fobjc-arc -Os -fvisibility=hidden -ffunction-sections -fdata-sections -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations
iPFakerAboutID_FRAMEWORKS = Foundation UIKit
iPFakerAboutID_LIBRARIES = substrate
iPFakerAboutID_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerAboutID.dylib -Wl,-dead_strip -Wl,-x

# AboutUI: delayed UILabel wash for host 15.5 → config ProductVersion (Preferences only)
iPFakerAboutUI_FILES = TweakAboutUI.x
iPFakerAboutUI_CFLAGS = -fobjc-arc -Os -fvisibility=hidden -ffunction-sections -fdata-sections -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations
iPFakerAboutUI_FRAMEWORKS = Foundation UIKit
iPFakerAboutUI_LIBRARIES = substrate
iPFakerAboutUI_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerAboutUI.dylib -Wl,-dead_strip -Wl,-x

# MG: spoof + Extra — must stay under AMFI ~145k (no About-only hooks linked in).
iPFakerMG_FILES = TweakMG.x src/IPFConfig.m src/IPFHooksMG.m src/IPFHooksExtra.m
# IPF_NO_MG_DEBUG=1 strips verbose ctor logs (AMFI size)
iPFakerMG_CFLAGS = -fobjc-arc -Os -fvisibility=hidden -DIPF_NO_MG_DEBUG=1 -ffunction-sections -fdata-sections -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerMG_FRAMEWORKS = UIKit Foundation AdSupport
iPFakerMG_LIBRARIES = substrate
iPFakerMG_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerMG.dylib -Wl,-dead_strip -Wl,-x

# CT: telephony + Deep + Env (locale/location/sensor) — Env was dead code before
iPFakerCT_FILES = TweakCT.x src/IPFConfig.m src/IPFHooksCT.m src/IPFHooksDeep.m src/IPFHooksEnv.m
iPFakerCT_CFLAGS = -fobjc-arc -Os -fvisibility=hidden -ffunction-sections -fdata-sections -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerCT_FRAMEWORKS = UIKit Foundation CoreTelephony CoreLocation CoreMotion
iPFakerCT_LIBRARIES = substrate
iPFakerCT_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerCT.dylib -Wl,-dead_strip

# JB: hide expand only (keep ~88k — proven inject). Server lives in iPFakerAA.
iPFakerJB_FILES = TweakJB.x src/IPFConfig.m src/IPFHooksJB.m
iPFakerJB_CFLAGS = -fobjc-arc -Os -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerJB_FRAMEWORKS = Foundation
iPFakerJB_LIBRARIES = substrate
iPFakerJB_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerJB.dylib -Wl,-dead_strip

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/etc/ipfaker$(ECHO_END)
	$(ECHO_NOTHING)chmod 755 layout/DEBIAN/postinst 2>/dev/null || true$(ECHO_END)

