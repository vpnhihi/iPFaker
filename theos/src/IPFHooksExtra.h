// IPFHooksExtra — UIScreen, disk capacity, JB path hide, boottime (sysctl)
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void IPFInstallExtraHooks(void);
/// Legacy lean (Safari-ish): getifaddrs · canOpenURL · ProcessInfo · optional UIScreen.
void IPFInstallExtraNetLeanHooks(void);
/// Zalo-safe only: NSProcessInfo OS string + hostName. No UIScreen / getifaddrs / path hide.
/// (UIScreen + MG screen-dimensions spoof crash Zalo UIFont/IsCompactDevice on A10.)
void IPFInstallExtraZaloSafeHooks(void);

#ifdef __cplusplus
}
#endif
