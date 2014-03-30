//
//  main.m
//  fmpsd
//
//  Created by August Mueller on 6/19/13.
//  Copyright (c) 2013 Flying Meat Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import "FMPSD.h"

void DumpLayer(FMPSDLayer *layer, NSString *baseName , int level)
{
    baseName = [NSString stringWithFormat:@"%@-%@", baseName, [layer layerName]];
    baseName = [baseName stringByReplacingOccurrencesOfString:@"/" withString:@"__"];
    @autoreleasepool {
        CGImageRef r = [layer image];
        if (r) {
            NSString *layerPath = [@"/tmp" stringByAppendingPathComponent:baseName];
            layerPath = [layerPath stringByAppendingPathExtension:@"png"];
            CGImageDestinationRef imageDestination = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:layerPath], @"public.png", 1, NULL);
            if (imageDestination) {
                CGImageDestinationAddImage(imageDestination, r, (__bridge CFDictionaryRef)[NSDictionary dictionary]);
                CGImageDestinationFinalize(imageDestination);
                CFRelease(imageDestination);
            } else {
                NSLog(@"Can't create destination at '%@'", layerPath);
            }
        }
    }
    for (FMPSDLayer *l in layer.layers) {
        @autoreleasepool {
            DumpLayer(l, baseName, level+1);
        }
    }
}


int main(int argc, const char * argv[])
{
    
    @autoreleasepool {
        
        
        NSString *path = nil;
        if (argc != 2) {
//            path = @"/Volumes/SnowLeopard/Users/airy/Sources/Others/fmpsd/fmpsd iOS Tests/images/iPad_GUI_1.0.psd";
        } else {
            path = [NSString stringWithUTF8String:argv[1]];
        }
        
        if (path == nil) {
            return 0;
        }
        NSError *err = nil;
        FMPSD *psd = [FMPSD imageWithContetsOfURL:[NSURL fileURLWithPath:path] error:&err];
        
        if (!psd) {
            NSLog(@"Error loading PSD: %@", err);
        }
        
//        [[psd baseLayerGroup] printTree:@""];
        
#if 1
        DumpLayer(psd.baseLayerGroup,[[path lastPathComponent] stringByDeletingPathExtension],0);
#else
        for (FMPSDLayer *l in [[psd baseLayerGroup] layers]) {
            @autoreleasepool {
                CGImageRef r = [l image];
                
                if (!r) {
                    NSLog(@" %@ - no image", l);
                    continue;
                }
                NSLog(@"%@", l.layerName);
                
                NSString *layerPath = [NSString stringWithFormat:@"/tmp/%@-Layer-%@.png", [[path lastPathComponent] stringByDeletingPathExtension], [l layerName]];
                
                CGImageDestinationRef imageDestination = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:layerPath], kUTTypePNG, 1, NULL);
                CGImageDestinationAddImage(imageDestination, r, (__bridge CFDictionaryRef)[NSDictionary dictionary]);
                CGImageDestinationFinalize(imageDestination);
                CFRelease(imageDestination);
            }
        }
#endif
    }
    return 0;
}

