# iPFaker split stack: MG (spoof+Extra) + CT (telephony+Deep) + JB (hide expand)
# Link libsubstrate.dylib (ElleKit), NOT CydiaSubstrate.framework (missing on Dopamine)

export TARGET := iphone:clang:latest:14.0
# Dual-arch: arm64 (A9–A11 e.g. iPhone 7) + arm64e (A12+ lab XS Max).
# Fat + proper ldid/trustcache on install (postinst). Thin arm64e-only broke new A10/A11 devices.
export ARCHS := arm64 arm64e
export THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

# HIOS-style 2 dylib only:
#   MG = identity + Extra + Deep + JB hide + SecItem/DeviceCheck/Proxy/WebRTC
#   CT = telephony + locale/location/sensor (CommCenter)
TWEAK_NAME = iPFakerMG iPFakerCT

# MG: full app-side wall (HIOS ChangeInfoIosMG equivalent)
iPFakerMG_FILES = TweakMG.x src/IPFConfig.m src/IPFHooksMG.m src/IPFHooksExtra.m src/IPFHooksDeep.m src/IPFHooksJB.m src/IPFHooksServerLite.m
iPFakerMG_CFLAGS = -fobjc-arc -Os -fvisibility=hidden -DIPF_NO_MG_DEBUG=1 -ffunction-sections -fdata-sections -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerMG_FRAMEWORKS = UIKit Foundation AdSupport Security
iPFakerMG_LIBRARIES = substrate
iPFakerMG_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerMG.dylib -Wl,-dead_strip -Wl,-x

# CT: telephony + Env only (Deep lives in MG to avoid double-hook)
iPFakerCT_FILES = TweakCT.x src/IPFConfig.m src/IPFHooksCT.m src/IPFHooksEnv.m
iPFakerCT_CFLAGS = -fobjc-arc -Os -fvisibility=hidden -ffunction-sections -fdata-sections -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerCT_FRAMEWORKS = UIKit Foundation CoreTelephony CoreLocation CoreMotion
iPFakerCT_LIBRARIES = substrate
iPFakerCT_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerCT.dylib -Wl,-dead_strip

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/etc/ipfaker$(ECHO_END)
	$(ECHO_NOTHING)chmod 755 layout/DEBIAN/postinst 2>/dev/null || true$(ECHO_END)

