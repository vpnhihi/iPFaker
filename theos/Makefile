# HIOS-style dual tweak (ChangeInfoIosMG + ChangeInfoIosCT)
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
TWEAK_NAME = iPFakerMG iPFakerCT iPFakerJB

# MG stays lean — no fopen/getenv/fileExists bulk (those → JB)
iPFakerMG_FILES = TweakMG.x src/IPFConfig.m src/IPFHooksMG.m src/IPFHooksExtra.m src/fishhook.c
iPFakerMG_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
# WebKit used only via runtime (objc_getClass) — hard-link WebKit broke Dopamine code-sign coverage
iPFakerMG_FRAMEWORKS = UIKit Foundation AdSupport
iPFakerMG_LIBRARIES = substrate
iPFakerMG_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerMG.dylib

# CT always loaded cleanly on Dopamine — carry network model rewrite here
iPFakerCT_FILES = TweakCT.x src/IPFConfig.m src/IPFHooksCT.m src/IPFHooksDeep.m
iPFakerCT_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerCT_FRAMEWORKS = UIKit Foundation CoreTelephony
iPFakerCT_LIBRARIES = substrate
iPFakerCT_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerCT.dylib

# JB expanded hide — small standalone; same bundle filter as MG
iPFakerJB_FILES = TweakJB.x src/IPFConfig.m src/IPFHooksJB.m
iPFakerJB_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerJB_FRAMEWORKS = Foundation
iPFakerJB_LIBRARIES = substrate
iPFakerJB_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerJB.dylib

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/etc/ipfaker$(ECHO_END)
	$(ECHO_NOTHING)chmod 755 layout/DEBIAN/postinst 2>/dev/null || true$(ECHO_END)

