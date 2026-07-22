#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
void IPFInstallMGHooks(void);
/// Settings → About only: MGCopyAnswer + UIDevice (no WithError/sysctl — avoids CoreRepair PAC crash)
void IPFInstallMGHooksLite(void);
#ifdef __cplusplus
}
#endif
