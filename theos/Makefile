# iPFaker split stack: MG (spoof+Extra) + CT (telephony+Deep) + JB (hide expand)
# Link libsubstrate.dylib (ElleKit), NOT CydiaSubstrate.framework (missing on Dopamine)

export TARGET := iphone:clang:latest:14.0
# arm64e only — fat binaries + manual thin often break ldid coverage on Dopamine
export ARCHS := arm64e
export THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

# Split stack (Dopamine AMFI):
#   MG = spoof + Extra core (screen/disk/UA/getifaddrs/access-stat)
#   CT = telephony + deep rewrite
#   JB = expanded hide (fopen/getenv/fileExists) — optional, fails independently
# AA = ServerLite (AppAttest/Proxy/WebRTC) — loads first alphabetically, tiny, no IPFConfig.m
TWEAK_NAME = iPFakerAA iPFakerMG iPFakerCT iPFakerJB

# MG = spoof + Extra (screen/disk/UA/getifaddrs/access-stat/WKWebView)
# fishhook.c OFF by default: keeps MG ~123k AMFI-safe. ElleKit MSHook is primary on Dopamine.
# Optional: add src/fishhook.c + -DIPF_FISHHOOK_FALLBACK=1 only if MSHook is unavailable.
# AA: server mitigations lite (AppAttest/Proxy/WebRTC) — own dylib, no CFNetwork, no IPFConfig.m
iPFakerAA_FILES = src/IPFHooksServerLite.m
iPFakerAA_CFLAGS = -fobjc-arc -Os -fvisibility=hidden -Wno-unused-variable -Wno-unused-function -I$(THEOS_PROJECT_DIR)/src
iPFakerAA_FRAMEWORKS = Foundation
iPFakerAA_LIBRARIES = substrate
iPFakerAA_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerAA.dylib -Wl,-dead_strip

# MG: spoof + Extra core only. Proven inject ≤128k on lab AMFI.
# Env (locale/location) optional — enable via IPF_WITH_ENV=1 if budget allows.
iPFakerMG_FILES = TweakMG.x src/IPFConfig.m src/IPFHooksMG.m src/IPFHooksExtra.m
# IPF_NO_MG_DEBUG=1 strips verbose ctor logs (AMFI size)
iPFakerMG_CFLAGS = -fobjc-arc -Os -fvisibility=hidden -DIPF_NO_MG_DEBUG=1 -ffunction-sections -fdata-sections -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerMG_FRAMEWORKS = UIKit Foundation AdSupport
iPFakerMG_LIBRARIES = substrate
iPFakerMG_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerMG.dylib -Wl,-dead_strip -Wl,-x

# CT lean: telephony + Deep (~105k inject OK)
iPFakerCT_FILES = TweakCT.x src/IPFConfig.m src/IPFHooksCT.m src/IPFHooksDeep.m
iPFakerCT_CFLAGS = -fobjc-arc -Os -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerCT_FRAMEWORKS = UIKit Foundation CoreTelephony
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

