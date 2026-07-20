# iPFaker.app — Shadow Tech–style lab UI (rootless, no Settings inject)
export TARGET := iphone:clang:latest:14.0
export ARCHS := arm64e
export THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = iPFaker

iPFaker_FILES = \
	main.m \
	AppDelegate.m \
	AppTheme.m \
	AppState.m \
	Catalog.m \
	AppCatalog.m \
	ProfileBuilder.m \
	ProgressOverlay.m \
	IPFCrypto.m \
	IPFLicenseManager.m \
	LoginViewController.m \
	MainViewController.m \
	SelectDevicesViewController.m \
	WipeViewController.m \
	SettingsViewController.m \
	DeviceListController.m \
	IOSListController.m \
	AppListController.m \
	AboutLabController.m \
	RootViewController.m

iPFaker_FRAMEWORKS = UIKit Foundation
iPFaker_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations
iPFaker_CODESIGN_FLAGS = -Sentitlements.plist
iPFaker_INSTALL_PATH = /Applications
iPFaker_RESOURCE_FILES = Resources/Info.plist Resources/device_catalog.json \
	Resources/AppIcon60x60@2x.png Resources/AppIcon60x60@3x.png \
	Resources/AppIcon-Small@2x.png Resources/AppIcon-Small@3x.png \
	Resources/AppIcon-Small-40@2x.png Resources/AppIcon-Small-40@3x.png

include $(THEOS_MAKE_PATH)/application.mk

after-stage::
	$(ECHO_NOTHING)chmod 755 layout/DEBIAN/postinst 2>/dev/null || true$(ECHO_END)
	$(ECHO_NOTHING)cp -f Resources/device_catalog.json $(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME).app/ 2>/dev/null || true$(ECHO_END)
	$(ECHO_NOTHING)cp -f Resources/ios_device_compat.json $(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME).app/ 2>/dev/null || true$(ECHO_END)
