#import "IPFContactsLab.h"
#import <Contacts/Contacts.h>

@implementation IPFContactsLab

+ (NSString *)seededListPath {
    return @"/var/mobile/Library/iPFaker/seeded_contacts.plist";
}

+ (NSString *)poolPath {
    for (NSString *p in @[
             @"/var/jb/etc/ipfaker/contacts_pool.txt",
             @"/var/mobile/Library/iPFaker/contacts_pool.txt",
             [[NSBundle mainBundle] pathForResource:@"contacts_pool" ofType:@"txt"] ?: @"",
         ]) {
        if (p.length && [[NSFileManager defaultManager] isReadableFileAtPath:p])
            return p;
    }
    return @"/var/mobile/Library/iPFaker/contacts_pool.txt";
}

+ (NSArray<NSString *> *)loadPoolLines {
    NSString *raw = [NSString stringWithContentsOfFile:[self poolPath]
                                              encoding:NSUTF8StringEncoding error:nil];
    if (!raw.length) {
        // Built-in mini pool if file missing
        return @[
            @"Nguyen Van A|0901000001",
            @"Tran Thi B|0901000002",
            @"Le Van C|0901000003",
            @"Pham Thi D|0901000004",
            @"Hoang Van E|0901000005",
            @"Vu Thi F|0901000006",
            @"Dang Van G|0901000007",
            @"Bui Thi H|0901000008",
            @"Do Van I|0901000009",
            @"Ngo Thi K|0901000010",
            @"Duong Van L|0901000011",
            @"Ly Thi M|0901000012",
            @"Truong Van N|0901000013",
            @"Phan Thi O|0901000014",
            @"Vo Van P|0901000015",
            @"Dinh Thi Q|0901000016",
            @"Lam Van R|0901000017",
            @"Mai Thi S|0901000018",
            @"Cao Van T|0901000019",
            @"To Thi U|0901000020",
        ];
    }
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *line in [raw componentsSeparatedByCharactersInSet:
                            [NSCharacterSet newlineCharacterSet]]) {
        NSString *t = [line stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length < 3 || [t hasPrefix:@"#"]) continue;
        [lines addObject:t];
    }
    return lines;
}

+ (NSString *)clearLabContacts {
    CNContactStore *store = [[CNContactStore alloc] init];
    CNAuthorizationStatus st = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
    if (st == CNAuthorizationStatusNotDetermined) {
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block BOOL ok = NO;
        [store requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError *e) {
            ok = granted; dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));
        if (!ok) return @"contacts: denied permission";
    } else if (st != CNAuthorizationStatusAuthorized) {
        return @"contacts: no permission";
    }

    NSArray *ids = [NSArray arrayWithContentsOfFile:[self seededListPath]];
    if (![ids isKindOfClass:[NSArray class]] || ids.count == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:[self seededListPath] error:nil];
        return @"contacts: no seeded list (nothing to clear)";
    }
    NSUInteger deleted = 0;
    NSError *err = nil;
    for (id oid in ids) {
        NSString *ident = [oid description];
        if (!ident.length) continue;
        NSArray *keys = @[ CNContactIdentifierKey, CNContactGivenNameKey, CNContactPhoneNumbersKey ];
        CNContact *c = [store unifiedContactWithIdentifier:ident keysToFetch:keys error:&err];
        if (!c) continue;
        CNSaveRequest *req = [[CNSaveRequest alloc] init];
        [req deleteContact:[c mutableCopy]];
        if ([store executeSaveRequest:req error:&err]) deleted++;
    }
    [[NSFileManager defaultManager] removeItemAtPath:[self seededListPath] error:nil];
    return [NSString stringWithFormat:@"contacts clear: removed %lu lab contacts", (unsigned long)deleted];
}

+ (NSString *)seedLabContactsCount:(NSUInteger)count {
    if (count == 0) count = 20;
    CNContactStore *store = [[CNContactStore alloc] init];
    CNAuthorizationStatus st = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
    if (st == CNAuthorizationStatusNotDetermined) {
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block BOOL ok = NO;
        [store requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError *e) {
            ok = granted; dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));
        if (!ok) return @"contacts seed: permission denied";
    } else if (st != CNAuthorizationStatusAuthorized) {
        return [NSString stringWithFormat:@"contacts seed: permission status=%ld", (long)st];
    }

    NSArray *pool = [self loadPoolLines];
    if (!pool.count) return @"contacts seed: empty pool";

    NSMutableArray *seededIds = [NSMutableArray array];
    NSUInteger created = 0;
    NSUInteger wanted = MIN(count, pool.count);
    // shuffle-ish: take from random offset
    NSUInteger start = arc4random_uniform((uint32_t)pool.count);
    for (NSUInteger i = 0; i < wanted; i++) {
        NSString *line = pool[(start + i) % pool.count];
        NSArray *parts = [line componentsSeparatedByString:@"|"];
        NSString *name = parts.count ? [parts[0] stringByTrimmingCharactersInSet:
                                        [NSCharacterSet whitespaceCharacterSet]] : @"Lab User";
        NSString *phone = parts.count > 1 ? [parts[1] stringByTrimmingCharactersInSet:
                                             [NSCharacterSet whitespaceCharacterSet]] : @"";
        if (!phone.length) phone = [NSString stringWithFormat:@"0901%06u", arc4random_uniform(1000000)];

        CNMutableContact *c = [[CNMutableContact alloc] init];
        // Mark lab contact in organization for debug
        c.organizationName = @"iPFaker Lab";
        NSArray *np = [name componentsSeparatedByString:@" "];
        if (np.count >= 2) {
            c.familyName = np[0];
            c.givenName = [[np subarrayWithRange:NSMakeRange(1, np.count - 1)] componentsJoinedByString:@" "];
        } else {
            c.givenName = name;
        }
        CNPhoneNumber *pn = [CNPhoneNumber phoneNumberWithStringValue:phone];
        c.phoneNumbers = @[ [CNLabeledValue labeledValueWithLabel:CNLabelPhoneNumberMobile value:pn] ];
        CNSaveRequest *req = [[CNSaveRequest alloc] init];
        [req addContact:c toContainerWithIdentifier:nil];
        NSError *err = nil;
        if ([store executeSaveRequest:req error:&err]) {
            if (c.identifier.length) [seededIds addObject:c.identifier];
            created++;
        }
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Library/iPFaker"
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [seededIds writeToFile:[self seededListPath] atomically:YES];
    return [NSString stringWithFormat:
            @"contacts seed: pool=%lu wanted=%lu created=%lu tracked=%lu",
            (unsigned long)pool.count, (unsigned long)wanted,
            (unsigned long)created, (unsigned long)seededIds.count];
}

+ (NSString *)resetLabContactsCount:(NSUInteger)count {
    NSString *c1 = [self clearLabContacts];
    NSString *c2 = [self seedLabContactsCount:count];
    return [NSString stringWithFormat:@"%@\n%@", c1, c2];
}

@end
