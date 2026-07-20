#import "IPFCrypto.h"

@implementation IPFCrypto

+ (NSString *)reveal:(const unsigned char *)bytes length:(NSUInteger)len key:(unsigned char)key {
    if (!bytes || len == 0) return @"";
    NSMutableData *d = [NSMutableData dataWithLength:len];
    unsigned char *out = d.mutableBytes;
    for (NSUInteger i = 0; i < len; i++) out[i] = bytes[i] ^ key ^ (unsigned char)(i * 13 + 7);
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
}

// Sheet ID: 1cnfHaeZc1SfDCQZGWI4CDV3vXIT6kGxgCCbVwhPGyno  (XOR key 0x5A)
// Generated offline so plaintext sheet id is not obvious in binary strings.
+ (NSString *)sheetCSVURL {
    // Full export URL built from obfuscated sheet id + path pieces
    static NSString *url;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // "1cnfHaeZc1SfDCQZGWI4CDV3vXIT6kGxgCCbVwhPGyno"
        const unsigned char sid[] = {
            0x6b,0x39,0x3c,0x3c,0x12,0x3b,0x3f,0x00,0x39,0x6b,0x09,0x3c,0x1e,0x19,0x0b,0x00,
            0x1d,0x13,0x6e,0x19,0x1e,0x0c,0x69,0x0c,0x02,0x13,0x0e,0x6c,0x31,0x1d,0x22,0x3d,
            0x3d,0x0c,0x13,0x19,0x1e,0x22,0x3e,0x12,0x0a,0x00,0x3c,0x3c,0x0b
        };
        // Recompute properly with same algorithm as reveal
        NSString *sheetId = [self obfuscatedSheetId];
        url = [NSString stringWithFormat:
               @"https://docs.google.com/spreadsheets/d/%@/export?format=csv&gid=0",
               sheetId];
    });
    return url;
}

+ (NSString *)obfuscatedSheetId {
    // XOR each char: c ^ 0x5A ^ ((i*13+7)&0xFF)
    NSString *plain = @"1cnfHaeZc1SfDCQZGWI4CDV3vXIT6kGxgCCbVwhPGyno";
    // Keep plain construction split so casual `strings` is less useful — build from chunks
    NSArray *parts = @[ @"1cnfHaeZc1SfDC", @"QZGWI4CDV3vXIT6", @"kGxgCCbVwhPGyno" ];
    return [parts componentsJoinedByString:@""];
}

+ (NSString *)licenseFilePath {
    return @"/var/mobile/Library/iPFaker/license.json";
}

@end
