# iPFaker — dual tweak package (MG + CT), rootless arm64
# Layout mirrors ChangeInfoIos / HIOS Faker v3 style deb.
#
# On macOS:
#   export THEOS=~/theos
#   cd theos && make package
#   # → packages/com.ipfaker.tweak_*_iphoneos-arm64.deb

export TARGET := iphone:clang:latest:15.0
export ARCHS := arm64 arm64e
export THEOS_PACKAGE_SCHEME := rootless

INSTALL_TARGET_PROCESSES = Zalo

include $(THEOS)/makefiles/common.mk

# ─── iPFakerMG — MobileGestalt / sysctl / UIDevice / IDFA ───
LIBRARY_NAME += iPFakerMG

iPFakerMG_FILES = \
	TweakMG.x \
	src/IPFConfig.m \
	src/IPFHooksMG.m

iPFakerMG_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerMG_FRAMEWORKS = UIKit Foundation AdSupport
iPFakerMG_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

# ─── iPFakerCT — CoreTelephony / carrier ────────────────────
LIBRARY_NAME += iPFakerCT

iPFakerCT_FILES = \
	TweakCT.x \
	src/IPFConfig.m \
	src/IPFHooksCT.m

iPFakerCT_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/src
iPFakerCT_FRAMEWORKS = UIKit Foundation CoreTelephony
iPFakerCT_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/library.mk

# Package extra files: filter plists + empty etc dir + postinst
after-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries$(ECHO_END)
	$(ECHO_NOTHING)cp -a $(THEOS_PROJECT_DIR)/layout/Library/MobileSubstrate/DynamicLibraries/*.plist \
		$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/etc/ipfaker$(ECHO_END)
	$(ECHO_NOTHING)cp -a $(THEOS_PROJECT_DIR)/layout/etc/ipfaker/* \
		$(THEOS_STAGING_DIR)/etc/ipfaker/ 2>/dev/null || true$(ECHO_END)
	$(ECHO_NOTHING)chmod 0755 $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/*.dylib 2>/dev/null || true$(ECHO_END)
	$(ECHO_NOTHING)chmod 0644 $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/*.plist 2>/dev/null || true$(ECHO_END)

after-install::
	install.exec "killall -9 Zalo 2>/dev/null || true; killall -9 CommCenter 2>/dev/null || true"
