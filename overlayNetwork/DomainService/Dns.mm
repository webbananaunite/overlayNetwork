//
//  Dns.m
//  blocks
//
//  Created by よういち on 2021/06/16.
//  Copyright © 2021 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <resolv.h>

@implementation Dns : NSObject
/*
 Thank:
 https://stackoverflow.com/a/26480097

 Should Set Xcode Build Setting
    Other Linker Flag
        -l resolv
 */
+ (NSArray<NSString *> *)fetchTXTRecords:(NSString *)domain
{
    // declare buffers / return array
    NSMutableArray *answers = [NSMutableArray new];
    u_char answer[1024];
    ns_msg msg;
    ns_rr rr;

    // initialize resolver
    res_init();

    // send query. res_query returns the length of the answer, or -1 if the query failed
    int rlen = res_query([domain cStringUsingEncoding:NSUTF8StringEncoding], ns_c_in, ns_t_txt, answer, sizeof(answer));

    if(rlen == -1)
    {
        return nil;
    }

    // parse the entire message
    if(ns_initparse(answer, rlen, &msg) < 0)
    {
        return nil;
    }

    // get the number of messages returned
    int rrmax = rrmax = ns_msg_count(msg, ns_s_an);

    // iterate over each message
    for(int i = 0; i < rrmax; i++)
    {
        // parse the answer section of the message
        if(ns_parserr(&msg, ns_s_an, i, &rr))
        {
            return nil;
        }

        // obtain the record data
        const u_char *rd = ns_rr_rdata(rr);

        // the first byte is the length of the data
        size_t length = rd[0];

        // create and save a string from the C string
        NSString *record = [[NSString alloc] initWithBytes:(rd + 1) length:length encoding:NSUTF8StringEncoding];
        [answers addObject:record];
    }

    return answers;
}
@end
