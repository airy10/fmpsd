//
//  fmpsd_iOS_Tests.m
//  fmpsd iOS Tests
//
//  Created by Airy André on 31/01/2014.
//  Copyright (c) 2014 Flying Meat Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <ImageIO/ImageIO.h>
#if TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#endif
#import "FMPSD.h"

@interface fmpsd_iOS_Tests : XCTestCase<FMPSDProviderDelegate>

@end

@implementation fmpsd_iOS_Tests

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
    NSString *layerName = [layer layerName];
    if (layerName == nil) {
        layerName = @"unamed";
    }
    baseName = [NSString stringWithFormat:@"%@-%@", baseName, layerName];
    if (layer.isComposite) {
        baseName = [baseName stringByAppendingString:@"-Composite"];
    }
    if (layer.isGroup) {
        baseName = [baseName stringByAppendingString:@"-Group"];
    }
    baseName = [baseName stringByReplacingOccurrencesOfString:@"/" withString:@"__"];
    @autoreleasepool {
        CGImageRef r = [layer image];
        if (r) {
            NSString *layerPath = [NSTemporaryDirectory() stringByAppendingPathComponent:baseName];
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
    for (FMPSDLayer *l in layer.layers) {
        @autoreleasepool {
            [self dumpLayer:l baseName:baseName level:level+1];
        }
    }
}

- (void)testExample
{
    NSArray *urls =  [[NSBundle bundleForClass:[self class]] URLsForResourcesWithExtension:@"psd" subdirectory:@"Tests"];
    for (NSURL *url in urls) {
        @autoreleasepool {
            NSLog(@"---- %@ -----", [url lastPathComponent]);
            FMPSD *psd = [FMPSD imageWithContetsOfURL:url error:nil];
            
            if (psd.compositeLayer) {
                [self dumpLayer:psd.compositeLayer baseName: [[url lastPathComponent] stringByAppendingString:@"-COMPOSITE-"] level:0];
            }
            [self dumpLayer:psd.baseLayerGroup baseName: [url lastPathComponent] level:0];
        }
    }
}

-(CGImageRef)imageForLayer:(FMPSDLayer *)layer
{
    NSURL *url = [[NSBundle bundleForClass:[self class]] URLForResource:layer.layerName withExtension:@"png" subdirectory:@"Tests"];
    UIImage *image = [UIImage imageWithContentsOfFile:[url path]];
    return image.CGImage;
}

- (void)testWrite
{
    CGRect frame = CGRectMake(0, 0, 1024, 768);
    
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/test.psd"];
    NSURL *url = [NSURL fileURLWithPath:path];
    
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
@end
