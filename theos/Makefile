# HIOS-style dual tweak (ChangeInfoIosMG + ChangeInfoIosCT)
# Link libsubstrate.dylib (ElleKit), NOT CydiaSubstrate.framework (missing on Dopamine)

export TARGET := iphone:clang:latest:14.0
# arm64e only — fat binaries + manual thin often break ldid coverage on Dopamine
export ARCHS := arm64e
export THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iPFakerMG iPFakerCT

# MG stays lean (device ldid/opainject was reliable without Deep.m bulk)
iPFakerMG_FILES = TweakMG.x src/IPFConfig.m src/IPFHooksMG.m src/IPFHooksExtra.m src/fishhook.c
iPFakerMG_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerMG_FRAMEWORKS = UIKit Foundation AdSupport WebKit
iPFakerMG_LIBRARIES = substrate
iPFakerMG_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerMG.dylib

# CT always loaded cleanly on Dopamine — carry network model rewrite here
iPFakerCT_FILES = TweakCT.x src/IPFConfig.m src/IPFHooksCT.m src/IPFHooksDeep.m
iPFakerCT_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerCT_FRAMEWORKS = UIKit Foundation CoreTelephony
iPFakerCT_LIBRARIES = substrate
iPFakerCT_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/iPFakerCT.dylib

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/etc/ipfaker$(ECHO_END)
	$(ECHO_NOTHING)chmod 755 layout/DEBIAN/postinst 2>/dev/null || true$(ECHO_END)

