//
//  Dns.h
//  Testy
//
//  Created by よういち on 2021/06/16.
//  Copyright © 2021 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//
#import <Foundation/Foundation.h>
@interface Dns {
    
}
+ (NSArray<NSString *> *)fetchTXTRecords:(NSString *)domain;

@end
