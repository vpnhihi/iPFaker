#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// HIOS-style RRS: backup session before wipe, optional restore.
@interface IPFRRS : NSObject
+ (NSString *)rrsRoot;
/// Step 0: backup selected app containers + config under rrs/<ts>/
+ (NSString *)backupBundles:(NSArray<NSString *> *)bundleIds progress:(void (^ _Nullable)(NSString *))progress;
/// Restore latest RRS snapshot (containers + config dual-path).
+ (NSString *)restoreLatestProgress:(void (^ _Nullable)(NSString *))progress;
/// Write wipe marker (Documents/.ipf_last_wipe + dual path).
+ (void)writeWipeMarkerForBundles:(NSArray<NSString *> *)bundleIds;
@end

NS_ASSUME_NONNULL_END
