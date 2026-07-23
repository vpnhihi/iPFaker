// IPFHooksExtra — UIScreen, disk capacity, JB path hide, boottime (sysctl)
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void IPFInstallExtraHooks(void);
/// Lean Zalo path (SkipExtraForZalo): identity that must not crash A10.
/// getifaddrs · gethostname · canOpenURL · NSProcessInfo OS/host · UIScreen.
/// Skips: WebKit inject, disk, access/stat path-hide storm.
void IPFInstallExtraNetLeanHooks(void);

#ifdef __cplusplus
}
#endif
