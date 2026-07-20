# HIOS-style dual tweak (ChangeInfoIosMG + ChangeInfoIosCT)
# Runtime-resolve MSHook from ElleKit — no hard link that breaks load

export TARGET := iphone:clang:latest:14.0
export ARCHS := arm64 arm64e
export THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iPFakerMG iPFakerCT

iPFakerMG_FILES = TweakMG.x src/IPFConfig.m src/IPFHooksMG.m
iPFakerMG_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerMG_FRAMEWORKS = UIKit Foundation AdSupport
# Do not link -lsubstrate (may fail load). Resolve MSHook via dlsym at runtime.
iPFakerMG_LDFLAGS = -Wl,-undefined,dynamic_lookup

iPFakerCT_FILES = TweakCT.x src/IPFConfig.m src/IPFHooksCT.m
iPFakerCT_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerCT_FRAMEWORKS = UIKit Foundation CoreTelephony
iPFakerCT_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/etc/ipfaker$(ECHO_END)
	$(ECHO_NOTHING)chmod 755 layout/DEBIAN/postinst 2>/dev/null || true$(ECHO_END)
