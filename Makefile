TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Instagram

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ReelsFullscreenToggle

ReelsFullscreenToggle_FILES = Tweak.xm
ReelsFullscreenToggle_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
