#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// HIOS-style lab contacts: seed from pool + clear only tracked lab contacts.
@interface IPFContactsLab : NSObject
+ (NSString *)seededListPath;
+ (NSString *)poolPath;
/// Delete only contacts previously seeded by iPFaker (tracked identifiers).
+ (NSString *)clearLabContacts;
/// Seed up to `count` contacts from pool (default 20). Tracks identifiers for clear.
+ (NSString *)seedLabContactsCount:(NSUInteger)count;
/// clear then seed (HIOS Step 1 style).
+ (NSString *)resetLabContactsCount:(NSUInteger)count;
@end

NS_ASSUME_NONNULL_END
