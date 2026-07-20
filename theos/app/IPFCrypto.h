#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Simple XOR string obfuscation for repo/GitHub (not military-grade; deters casual scrape).
@interface IPFCrypto : NSObject
+ (NSString *)reveal:(const unsigned char *)bytes length:(NSUInteger)len key:(unsigned char)key;
+ (NSString *)sheetCSVURL;
+ (NSString *)licenseFilePath;
@end

NS_ASSUME_NONNULL_END
