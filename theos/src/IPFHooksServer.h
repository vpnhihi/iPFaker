// Server-side client mitigations (Proxy / AppAttest / WebRTC IP) — packed into CT
// to keep MG Extra AMFI-safe (~≤130k). Same dual-path IPFConfig as MG/CT/JB.
#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
void IPFInstallServerHooks(void);
#ifdef __cplusplus
}
#endif
