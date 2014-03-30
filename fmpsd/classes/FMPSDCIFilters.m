//
//  FMPSDCIFilters.m
//  fmpsd
//
//  Created by August Mueller on 10/26/10.
//  Copyright 2010 Flying Meat Inc. All rights reserved.
//

#import "FMPSDCIFilters.h"

static CIKernel *FMPSDAlphaFilterKernel = nil;

@implementation FMPSDAlphaFilter

@synthesize alpha=_alpha;
@synthesize inputImage=_inputImage;

+ (CIFilter *)filterWithName:(NSString *)name {
    return [[self alloc] init];
}

- (id)init {
    if (FMPSDAlphaFilterKernel == nil) {
#if !TARGET_OS_IPHONE
        NSString *code = @"\
                          kernel vec4 alf(sampler src, float a) {\n\
                          vec4 result = unpremultiply(sample(src, samplerCoord(src)));\n\
                          result.a = result.a * a;\n\
                          return premultiply(result);\n\
                          }";
        
        NSArray *kernels = [CIKernel kernelsWithString:code];
        
        FMPSDAlphaFilterKernel = [kernels objectAtIndex:0];
#endif
    }
    return [super init];
}

- (NSArray *)inputKeys {
    return [NSArray arrayWithObjects:@"inputImage", @"alpha", nil];
}

- (NSDictionary *)customAttributes {
    return [NSDictionary dictionary];
}

- (CIImage *)outputImage {
#if TARGET_OS_IPHONE
    return _inputImage;
#else
    CISampler *src = [CISampler samplerWithImage:_inputImage];
    
    return [self apply:FMPSDAlphaFilterKernel, src, _alpha, nil];
#endif
}


@end
