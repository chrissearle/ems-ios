//
//  EMSAdvancedSearch.m
//

#import "EMSAdvancedSearch.h"

@interface EMSAdvancedSearch ()

@property(nonatomic, strong) NSString *searchText;
@property(nonatomic, strong) NSMutableDictionary *fields;

@end

@implementation
EMSAdvancedSearch

NSString *const PrefsSearchText = @"searchText";
NSString *const PrefsSearchField = @"searchFields";

- (id)init {
    self = [super init];

    if (self) {
        self.searchText = @"";
        self.fields = [[NSMutableDictionary alloc] init];
    }

    [self retrieve];

    return self;
}

- (NSString *)search {
    return [NSString stringWithString:self.searchText];
}

- (void)setSearch:(NSString *)search {
    self.searchText = [NSString stringWithString:search];

    [self persist];
}

- (NSSet *)fieldValuesForKey:(EMSSearchField)key {
    NSNumber *k = @(key);

    if ([self.fields.allKeys containsObject:k]) {
        return [NSSet setWithSet:self.fields[k]];
    }

    return [NSSet set];
}

- (void)setFieldValues:(NSSet *)values forKey:(EMSSearchField)key {
    NSNumber *k = @(key);

    if (values != nil) {
        self.fields[k] = values;
    } else {
        self.fields[k] = [NSSet set];
    }

    [self persist];
}

- (void)persist {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    [defaults setObject:self.searchText forKey:PrefsSearchText];

    NSMutableDictionary *fieldsAsArrays = [[NSMutableDictionary alloc] init];

    for (int i = emsKeyword; i <= emsLang; i++) {
        NSNumber *key = @(i);

        if ([[self.fields allKeys] containsObject:key]) {
            fieldsAsArrays[[key stringValue]] = [self.fields[key] allObjects];
        }
    }
    [defaults setObject:[NSDictionary dictionaryWithDictionary:fieldsAsArrays] forKey:PrefsSearchField];

    [defaults synchronize];

    if ([EMSFeatureConfig isCrashlyticsEnabled]) {
        [Crashlytics setObjectValue:self.searchText forKey:@"lastStoredSearchText"];
        [Crashlytics setObjectValue:self.fields forKey:@"lastStoredSearchFields"];
    }
}

- (void)retrieve {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSString *storedSearchText = [defaults objectForKey:PrefsSearchText];
    if (storedSearchText != nil) {
        self.searchText = [NSString stringWithString:storedSearchText];
    }

    NSDictionary *storedSearchFields = [defaults objectForKey:PrefsSearchField];

    if (storedSearchFields != nil) {
        for (int i = emsKeyword; i <= emsLang; i++) {
            NSString *key = [@(i) stringValue];

            [self setFieldValues:[[storedSearchFields allKeys] containsObject:key] ? [NSSet setWithArray:storedSearchFields[key]] : [NSSet set] forKey:i];
        }
    }

    if ([EMSFeatureConfig isCrashlyticsEnabled]) {
        [Crashlytics setObjectValue:self.searchText forKey:@"lastRetrievedSearchText"];
        [Crashlytics setObjectValue:self.fields forKey:@"lastRetrievedSearchFields"];
    }
}

- (BOOL)hasAdvancedSearch {
    return ([[self fieldValuesForKey:emsKeyword] count] > 0 ||
            [[self fieldValuesForKey:emsLevel] count] > 0 ||
            [[self fieldValuesForKey:emsType] count] > 0 ||
            [[self fieldValuesForKey:emsRoom] count] > 0 ||
            [[self fieldValuesForKey:emsLang] count] > 0);
}

- (void)clear {
    [self setSearch:@""];

    for (int i = emsKeyword; i <= emsLang; i++) {
        [self setFieldValues:[NSSet set] forKey:i];
    }
}

@end
