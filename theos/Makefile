# iPFaker — dual TWEAK package mirroring ChangeInfoIos / HIOS v3 layout
# HIOS: ChangeInfoIosMG.dylib + ChangeInfoIosCT.dylib under TweakInject
# Config: /var/jb/etc/ipfaker/config.plist (flat keys, like changeinfoios/config.plist)

export TARGET := iphone:clang:latest:14.0
export ARCHS := arm64 arm64e
export THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

# Use TWEAK_NAME (not LIBRARY_NAME) so Theos builds Substrate-loadable dylibs
TWEAK_NAME = iPFakerMG iPFakerCT

# ─── MG: Gestalt + sysctl + UIDevice + IDFA (ChangeInfoIosMG) ───
iPFakerMG_FILES = TweakMG.x src/IPFConfig.m src/IPFHooksMG.m
iPFakerMG_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerMG_FRAMEWORKS = UIKit Foundation AdSupport IOKit
# Link Substrate/ElleKit MSHook* (required — otherwise dylib fails to load)
iPFakerMG_LIBRARIES = substrate
iPFakerMG_LDFLAGS = -Wl,-undefined,dynamic_lookup

# ─── CT: CoreTelephony (ChangeInfoIosCT) ───
iPFakerCT_FILES = TweakCT.x src/IPFConfig.m src/IPFHooksCT.m
iPFakerCT_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerCT_FRAMEWORKS = UIKit Foundation CoreTelephony
iPFakerCT_LIBRARIES = substrate
iPFakerCT_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/etc/ipfaker$(ECHO_END)
	$(ECHO_NOTHING)cp -a $(THEOS_PROJECT_DIR)/layout/etc/ipfaker/* $(THEOS_STAGING_DIR)/etc/ipfaker/ 2>/dev/null || true$(ECHO_END)
	$(ECHO_NOTHING)chmod 755 layout/DEBIAN/postinst 2>/dev/null || true$(ECHO_END)

after-install::
	install.exec "killall -9 Zalo 2>/dev/null || true"
