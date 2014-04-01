//
//  fmpsd_iOS_Tests.m
//  fmpsd iOS Tests
//
//  Created by Airy André on 31/01/2014.
//  Copyright (c) 2014 Flying Meat Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <ImageIO/ImageIO.h>
#import "FMPSD.h"

@interface fmpsd_Mac_Tests : XCTestCase <FMPSDProviderDelegate>

@end

@implementation fmpsd_Mac_Tests
- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)dumpLayer:(FMPSDLayer *)layer baseName:(NSString *)baseName level:(int)level
{
    [[NSFileManager defaultManager] createDirectoryAtPath:baseName withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *layerName = [layer layerName];
    if (layerName == nil || layer == layer.psd.baseLayerGroup) {
        layerName = @"";
    }
    if (layer.isGroup && layer != layer.psd.baseLayerGroup) {
        baseName = [baseName stringByAppendingPathComponent:layerName];
    }
    if (layer.isComposite) {
        layerName = [layerName stringByAppendingString:@"Composite"];
    }
    if (layer.isGroup) {
        layerName = [layerName stringByAppendingString:@"Group"];
    }
    layerName = [layerName stringByReplacingOccurrencesOfString:@"/" withString:@"__"];
    if (layerName.length == 0) {
        layerName = @"<untitled>";
    }
    @autoreleasepool {
        [[NSFileManager defaultManager] createDirectoryAtPath:baseName withIntermediateDirectories:YES attributes:nil error:NULL];
        CGImageRef r = [layer image];
        if (r) {
            NSString *layerPath = baseName;
            if (layer != layer.psd.baseLayerGroup) {
                layerPath  = [layerPath stringByAppendingPathComponent:layerName];
            }
            layerPath = [layerPath stringByAppendingPathExtension:@"png"];
            CGImageDestinationRef imageDestination = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:layerPath], kUTTypePNG, 1, NULL);
            if (imageDestination) {
                CGImageDestinationAddImage(imageDestination, r, (__bridge CFDictionaryRef)[NSDictionary dictionary]);
                CGImageDestinationFinalize(imageDestination);
                CFRelease(imageDestination);
            } else {
                NSLog(@"Can't create destination at '%@'", layerPath);
            }
        }
    }
    if (layer.isGroup && layer != layer.psd.baseLayerGroup) {
        NSString *layerName = @"Merged";
        @autoreleasepool {
            [[NSFileManager defaultManager] createDirectoryAtPath:baseName withIntermediateDirectories:YES attributes:nil error:NULL];
            CIImage *img = [layer CIImageForComposite];
            if (img.extent.size.width > 0 && img.extent.size.height > 0) {
#if TARGET_OS_IPHONE
                // [[CIContext alloc] init] doesn't work fine on iOS - we get only last image from the chain
                CIContext *ctx = [CIContext contextWithOptions:0];
#else
                CIContext *ctx = [[CIContext alloc] init];
#endif
                CGImageRef r = [ctx createCGImage:img fromRect:CGRectMake(0, 0, img.extent.size.width, img.extent.size.height)];
                
                if (r) {
                    NSString *layerPath = baseName;
                    if (layer != layer.psd.baseLayerGroup) {
                        layerPath  = [layerPath stringByAppendingPathComponent:layerName];
                    }
                    layerPath = [layerPath stringByAppendingPathExtension:@"png"];
                    CGImageDestinationRef imageDestination = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:layerPath], kUTTypePNG, 1, NULL);
                    if (imageDestination) {
                        CGImageDestinationAddImage(imageDestination, r, (__bridge CFDictionaryRef)[NSDictionary dictionary]);
                        CGImageDestinationFinalize(imageDestination);
                        CFRelease(imageDestination);
                    } else {
                        NSLog(@"Can't create destination at '%@'", layerPath);
                    }
                }
            }
        }

    }
    for (FMPSDLayer *l in layer.layers) {
        @autoreleasepool {
            [self dumpLayer:l baseName:baseName level:level+1];
        }
    }
}

- (void)testRead
{
    NSString *baseDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"fmpsd-testRead"];
    NSArray *urls =  [[NSBundle bundleForClass:[self class]] URLsForResourcesWithExtension:@"psd" subdirectory:@"Tests"];
    for (NSURL *url in urls) {
        @autoreleasepool {
            NSLog(@"---- %@ -----", [url lastPathComponent]);
            FMPSD *psd = [FMPSD imageWithContetsOfURL:url error:nil];
            NSString *baseName = [baseDirectory stringByAppendingPathComponent:[[url lastPathComponent] stringByDeletingPathExtension]];
            if (psd.compositeLayer) {
                [self dumpLayer:psd.compositeLayer baseName:baseName level:0];
            }
            [self dumpLayer:psd.baseLayerGroup baseName: baseName level:0];
        }
    }
    [[NSWorkspace sharedWorkspace] openFile:baseDirectory];
}

-(CGImageRef)imageForLayer:(FMPSDLayer *)layer
{
    NSURL *url = [[NSBundle bundleForClass:[self class]] URLForResource:layer.layerName withExtension:@"png" subdirectory:@"Tests"];
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    NSRect r = NSZeroRect;
    r.size = layer.frame.size;
    [image lockFocus];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:r];
    [image unlockFocus];
    return rep.CGImage;
}

- (void)testWrite
{
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

- (void)testWriteGroup
{
    NSRect frame = NSMakeRect(0, 0, 1024, 768);
    
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/group.psd"];
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

    FMPSDLayer *group = [FMPSDLayer layerWithSize:CGSizeZero psd:psd];
    group.layerName = @"Sketch";
    [layer addLayerToGroup:group];
    group.isGroup = YES;
    
    sublayer = [FMPSDLayer layerWithSize:frame.size psd:psd];
    sublayer.frame = frame;
    sublayer.layerName = @"Layer1";
    [group addLayerToGroup:sublayer];
    
    group = [FMPSDLayer layerWithSize:CGSizeZero psd:psd];
    group.layerName = @"Color";
    [layer addLayerToGroup:group];
    group.isGroup = YES;
    
    sublayer = [FMPSDLayer layerWithSize:frame.size psd:psd];
    sublayer.layerName = @"Layer2";
    sublayer.frame = frame;
    [group addLayerToGroup:sublayer];
    
    group = [FMPSDLayer layerWithSize:CGSizeZero psd:psd];
    group.layerName = @"Inking";
    [layer addLayerToGroup:group];
    group.isGroup = YES;
    
    sublayer = [FMPSDLayer layerWithSize:frame.size psd:psd];
    sublayer.layerName = @"Layer3";
    sublayer.frame = frame;
    [group addLayerToGroup:sublayer];
    
    [psd writeToFile:url];
}

@end
