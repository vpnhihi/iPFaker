// IPFHooksExtra — UIScreen, disk capacity, JB path hide, boottime (sysctl)
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void IPFInstallExtraHooks(void);
/// Lean net+JB medium for Zalo when SkipExtraForZalo (no UIScreen/WebKit/disk).
/// Only: getifaddrs MAC · gethostname · canOpenURL JB schemes.
void IPFInstallExtraNetLeanHooks(void);

#ifdef __cplusplus
}
#endif
