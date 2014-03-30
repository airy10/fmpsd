//
//  AppDelegate.m
//  fmpsd Mac
//
//  Created by Airy André on 28/03/2014.
//  Copyright (c) 2014 Flying Meat Inc. All rights reserved.
//

#import "AppDelegate.h"
#import "FMPSD.h"

@implementation AppDelegate

-(CGImageRef)imageForLayer:(FMPSDLayer *)layer
{
    NSURL *url = [[NSBundle bundleForClass:[self class]] URLForImageResource:layer.layerName];
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    NSRect r = NSZeroRect;
    r.size = layer.frame.size;
    [image lockFocus];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:r];
    [image unlockFocus];
    return rep.CGImage;
}
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
#if 0
    for (int i = 0; i < 100; ++i) {
        @autoreleasepool {
            NSRect frame = NSMakeRect(0, 0, 1024, 768);
            
            NSURL *url = [NSURL fileURLWithPath:@"/tmp/test.psd"];
            
            FMPSD *psd = [[FMPSD alloc] init];
            psd.width = frame.size.width;
            psd.height = frame.size.height;
            psd.depth = 8;
            
            psd.delegate = self;
            
            FMPSDLayer *sublayer = nil;
            
            FMPSDLayer *layer = [psd baseLayerGroup];
            layer.psd = psd;
            layer.width = frame.size.width;
            layer.height = frame.size.height;
            
            sublayer = [FMPSDLayer layerWithSize:frame.size psd:psd];
            sublayer.frame = frame;
            sublayer.layerName = @"Layer1";
            [layer addLayerToGroup:sublayer];
            sublayer = [FMPSDLayer layerWithSize:frame.size psd:psd];
            sublayer.layerName = @"Layer2";
            sublayer.frame = frame;
            [layer addLayerToGroup:sublayer];
            sublayer = [FMPSDLayer layerWithSize:frame.size psd:psd];
            sublayer.layerName = @"Layer3";
            sublayer.frame = frame;
            [layer addLayerToGroup:sublayer];
            
            [psd writeToFile:url];
        }
    }
#endif
}

@end
