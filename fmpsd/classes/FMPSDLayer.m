//
//  FMPSDLayer.m
//  fmpsd
//
//  Created by August Mueller on 10/22/10.
//  Copyright 2010 Flying Meat Inc. All rights reserved.
//

#import "FMPSDLayer.h"
#import "FMPSD.h"
#import "FMPSDUtils.h"
#import "FMPSDCIFilters.h"
#import "FMPSDTextEngineParser.h"
#import <ImageIO/ImageIO.h>
#import <Accelerate/Accelerate.h>

static size_t encodeRLE(const uint8_t *buf, uint8_t* output, size_t size)
{
    char b[127];
    unsigned int bdex = 0, i = 0, j = 0, t = 0;
    
    do {
        /* zero the line index */
        i = 0;
        
        /* check for a run of at least three bytes */
        while((t + i + 3 < size) && (i < 126) && (buf[t + i] == buf[t + i + 1]) &&
              (buf[t + i] == buf[t + i + 2])) {
            i++;
        }
        /* if there's a run... */
        if((i > 0 && bdex > 0) || (bdex >= 127))
        {
            /* if there's a literal string... */
            if (output)  *output++ = bdex - 1;
            j++;
            /* write it to the output buffer. */
            if (output)  memcpy(output, b, bdex);
            if (output)  output += bdex;
            j += bdex;
            bdex = 0;
        }
        if(i > 0)
        {
            /* and then write the run. */
            i += 2;
            if (output)  *output++ = 257-i;
            if (output)  *output++ = buf[t];
            t += i;
            j += 2;
        }
        else
        {
            b[bdex++] = buf[t++];
        }
    } while(t < size);
    if(bdex)
    {
        /* if there's a literal string... */
        if (output) *output++ = bdex - 1;
        j++;
        /* write it to the output buffer. */
        if (output)  memcpy(output, b, bdex);
        j += bdex;
    }
    
    return j;
}

@interface FMPSDLayer()
- (BOOL)readLayerInfo:(FMPSDStream*)stream error:(NSError**)err;
@end

@implementation FMPSDLayer

+ (id)baseLayer {
    
    FMPSDLayer *ret = [[self alloc] init];
    
    ret->_isBase = YES;
    
    [ret setLayerName:@"<Internal Base Layer>"];
    [ret setIsGroup:YES];
    
    return ret;
}

+ (id)layerWithSize:(CGSize)s psd:(FMPSD*)psd {
    
    FMPSDLayer *ret = [[self alloc] init];
    [ret setPsd:psd];
    
    [ret setWidth:s.width];
    [ret setHeight:s.height];
    
    [ret setRight:s.width];
    
    [ret setBottom:[ret height]];
    
    return ret;
}

+ (id)layerWithStream:(FMPSDStream*)stream psd:(FMPSD*)psd error:(NSError**)err {
    
    FMPSDLayer *ret = [[self alloc] init];
    
    [ret setPsd:psd];
    
    if (![ret readLayerInfo:stream error:err]) {
        return 0x00;
    }
    
    return ret;
}

- (id)init {
	self = [super init];
	if (self != nil) {
		_visible = YES;
        _opacity = 255;
        _blendMode = 'norm';
	}
	return self;
}


- (void)dealloc {
    
    _stream = nil;
    if (_image) {
        CGImageRelease(_image);
        _image = nil;
    }
    
}

- (void)writeGroupMarkerToStream:(FMPSDStream*)stream {
    
    [stream writeInt32:0]; // top
    [stream writeInt32:0]; // left
    [stream writeInt32:0]; // bottom
    [stream writeInt32:0]; // right
    [stream writeInt16:4]; // channels
    
    // channel info
    [stream writeSInt16:-1]; // id
    [stream writeInt32:2];   // length
    [stream writeInt16:0];   // id
    [stream writeInt32:2];   // length
    [stream writeInt16:1];   // id
    [stream writeInt32:2];   // length
    [stream writeInt16:2];   // id
    [stream writeInt32:2];   // length
    
    [stream writeInt32:'8BIM'];
    [stream writeInt32:'norm']; // blend mode
    [stream writeInt8:255]; // opactiy
    [stream writeInt8:0]; //clipping Clipping: 0 = base, 1 = non–base
    
    uint8_t flags = 10;
    if (!_transparencyProtected && _visible) {
        flags = 8;
    }
    else if (_transparencyProtected && _visible) {
        flags = 9;
    }
    else if (_transparencyProtected && !_visible) {
        flags = 11;
    }
    [stream writeInt8:flags];
    
    [stream writeInt8:0]; // filler.
    
    FMPSDStream *extraDataStream = [FMPSDStream PSDStreamForWritingToMemory];
    
    // Layer mask data. TABLE 1.18
    [extraDataStream writeInt32:0];
    
    // Layer blending ranges: See Table 1.19.
    [extraDataStream writeInt32:0];
    
#ifdef DEBUG
    long loc = [extraDataStream location];
#endif
    NSString *groupEndMarkerName = @"</Layer group>";
    // Layer name: Pascal string, padded to a multiple of 4 bytes.
    [extraDataStream writePascalString:groupEndMarkerName withPadding:4];
    
    FMAssert((([extraDataStream location] - loc) % 4) == 0); // padding has to be to 4!
    
    
    [extraDataStream writeInt32:'8BIM'];
    [extraDataStream writeInt32:'lsct'];
    [extraDataStream writeInt32:sizeof(uint32_t)];
    [extraDataStream writeInt32:3]; // 3 = FMPSDLayerTypeHidden
    
    [extraDataStream writeInt32:'8BIM'];
    [extraDataStream writeInt32:'luni']; // unicode version of string.
    
    NSRange r = NSMakeRange(0, [groupEndMarkerName length]);
    [extraDataStream writeInt32:(uint32_t)(r.length * 2) + 4]; // length of the next bit of data.
    
    // length of our data as a unicode string.
    [extraDataStream writeInt32:(uint32_t)r.length];
    
    unichar *buffer = malloc(sizeof(unichar) * ([groupEndMarkerName length] + 1));
    
    [groupEndMarkerName getCharacters:buffer range:r];
    buffer[([groupEndMarkerName length] + 1)] = 0;
    
    for (NSUInteger i = 0; i < [groupEndMarkerName length]; i++) {
        [extraDataStream writeInt16:buffer[i]];
    }
    
    [stream writeDataWithLengthHeader:[extraDataStream outputData]];
    
    free(buffer);
}

- (uint32_t)sizeForPlane:(uint8_t *)plane isMask:(BOOL)isMask
{
    BOOL useRLE = YES;
    int width = isMask?_maskWidth:_width;
    int height = isMask?_maskHeight:_height;
    size_t len = 0;
    if (useRLE) {
        size_t compressedLength = 0;
        for (int i = 0; i < height; ++i) {
            compressedLength += encodeRLE(plane + i * width, NULL, width);
        }
        size_t uncompressedLen = width * height;
        if (uncompressedLen > compressedLength + sizeof(uint16_t) * height) {
            len = compressedLength + sizeof(uint16_t) * height;
        } else {
            len = width * height;
        }
    } else {
        len = width * height;
    }
    return (uint32_t)len;
}

- (void)getPlanesR:(uint8_t **)rPlane g:(uint8_t **)gPlane b:(uint8_t **)bPlane a:(uint8_t **)aPlane m:(uint8_t **)mPlane
{
    CGImageRef image = _image;
    if (image == NULL && self.psd.delegate) {
        image = [self.psd.delegate imageForLayer:self];
    }
    if (image == NULL) {
        *aPlane = *rPlane = *gPlane = *bPlane = *mPlane = NULL;
        return;
    }

#if TARGET_OS_IPHONE
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
#else
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
#endif
    CGContextRef ctx = CGBitmapContextCreate(nil, _width, _height, 8, _width * 4, cs, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    
    CGColorSpaceRelease(cs);
    
    CGContextSetBlendMode(ctx, kCGBlendModeCopy);
    CGContextDrawImage(ctx, CGRectMake(0, 0, _width, _height), image);
    
    
    FMPSDPixel *c = CGBitmapContextGetData(ctx);
    
    // let's unpremultiply this guy - but not if we're a composite!
    // let's unpremultiply this guy - but not if we're a composite!
    if (!_isComposite) {
        
        // FIXME: delete the old unpremultiply code.
        //        Old code.  I'm keeping it around for a moment, just incase vImageUnpremultiplyData_RGBA8888 doesn't work out for some reason.
#if 0
        dispatch_queue_t queue = dispatch_get_global_queue(0, DISPATCH_QUEUE_PRIORITY_HIGH);
        
        dispatch_apply(_height, queue, ^(size_t row) {
            
            FMPSDPixel *p = &c[_width * row];
            
            int32_t x = 0;
            while (x < _width) {
                
                if (p->a != 0) {
                    p->r = (p->r * 255 + p->a / 2) / p->a;
                    p->g = (p->g * 255 + p->a / 2) / p->a;
                    p->b = (p->b * 255 + p->a / 2) / p->a;
                }
                
                p++;
                x++;
            }
        });
#else
        vImage_Buffer buf;
        buf.data = c;
        buf.width = _width;
        buf.height = _height;
        buf.rowBytes = CGBitmapContextGetBytesPerRow(ctx);
        
        vImage_Error err = vImageUnpremultiplyData_RGBA8888(&buf, &buf, 0);
        
        if (err != kvImageNoError) {
            NSLog(@"FMPSDLayer writeImageDataToStream: vImageUnpremultiplyData_RGBA8888 err: %ld", err);
        }
#endif
    } else {
        dispatch_queue_t queue = dispatch_get_global_queue(0, DISPATCH_QUEUE_PRIORITY_HIGH);
        
        dispatch_apply(_height, queue, ^(size_t row) {
            
            FMPSDPixel *p = &c[_width * row];
            
            // Looks like PS is actually blending the colors to a white background, while keeping the
            // alpha value
            int32_t x = 0;
            while (x < _width) {
                unsigned long s1a = 0xff - p->a;
                p->r = (uint8_t)(p->r + ((0xff * s1a + 0xff) >> 8));
                p->g = (uint8_t)(p->g + ((0xff * s1a + 0xff) >> 8));
                p->b = (uint8_t)(p->b + ((0xff * s1a + 0xff) >> 8));
                
                p++;
                x++;
            }
        });
    }
    
    size_t len      = _width * _height;
    size_t maskLen  = _maskWidth * _maskHeight;
    
    uint8_t *r = malloc(sizeof(uint8_t) * len);
    uint8_t *g = malloc(sizeof(uint8_t) * len);
    uint8_t *b = malloc(sizeof(uint8_t) * len);
    uint8_t *a = malloc(sizeof(uint8_t) * len);
    uint8_t *m = nil;
    
    // split it up into planes
    size_t j = 0;
    while (j < len) {
        
        FMPSDPixel p = c[j];
        
        a[j] = p.a;
        r[j] = p.r;
        g[j] = p.g;
        b[j] = p.b;
        
        j++;
    }
    
    CGContextRelease(ctx);
    
    
    if (_mask) {
        
        m   = malloc(sizeof(char) * maskLen);
#if TARGET_OS_IPHONE
        cs  = CGColorSpaceCreateDeviceGray();
#else
        cs  = CGColorSpaceCreateWithName(kCGColorSpaceGenericGray);
#endif
        ctx = CGBitmapContextCreate(m, _maskWidth, _maskHeight, 8, _maskWidth, cs, (CGBitmapInfo)kCGImageAlphaNone);
        CGColorSpaceRelease(cs);
        CGContextDrawImage(ctx, CGRectMake(0, 0, _maskWidth, _maskHeight), _mask);
        CGContextRelease(ctx);
        
    }
    
    *aPlane = a;
    *rPlane = r;
    *gPlane = g;
    *bPlane = b;
    *mPlane = m;
}

- (void)writeLayerInfoToStream:(FMPSDStream*)stream {
    
    if (_isGroup) {
        
        [self writeGroupMarkerToStream:stream];
        
        for (FMPSDLayer *layer in [[self layers] reverseObjectEnumerator]) {
            [layer writeLayerInfoToStream:stream];
        }
    }
    
    [stream writeInt32:_top];
    [stream writeInt32:_left];
    [stream writeInt32:_bottom];
    [stream writeInt32:_right];
    
    [stream writeInt16:_mask ? 5 : 4]; // channels.
    
    // argb.  At least, that's the order PS writes it out in it seems.
    // total of 26 bytes in case you're worndering.
    // the + 2 is for the compression flag?
    uint8_t *r, *g, *b, *a, *m;
    [self getPlanesR:&r g:&g b:&b a:&a m:&m];
    
    [stream writeSInt16:-1];    // A plane
    [stream writeInt32:[self sizeForPlane:a isMask:NO] + 2];
    [stream writeInt16:0];      // R plane
    [stream writeInt32:[self sizeForPlane:r isMask:NO] + 2];
    [stream writeInt16:1];      // G plane
    [stream writeInt32:[self sizeForPlane:g isMask:NO] + 2];
    [stream writeInt16:2];      // B plane
    [stream writeInt32:[self sizeForPlane:b isMask:NO] + 2];
    
    if (_mask) {
        [stream writeInt16:-2]; // mask plane
        [stream writeInt32:[self sizeForPlane:m isMask:YES] + 2];
    }
    
    free(a);
    free(r);
    free(g);
    free(b);
    free(m);

    [stream writeInt32:'8BIM'];
    [stream writeInt32:_blendMode];
    [stream writeInt8:_opacity];
    [stream writeInt8:0]; //clipping Clipping: 0 = base, 1 = non–base
    
    // uint8_t f = ((_visible << 0x01) | _transparencyProtected);
    uint8_t flags = 10;
    if (!_transparencyProtected && _visible) {
        flags = 8;
    }
    else if (_transparencyProtected && _visible) {
        flags = 9;
    }
    else if (_transparencyProtected && !_visible) {
        flags = 11;
    }
    
    [stream writeInt8:flags]; // this is the flags stuff.  visible, preserve transparency, etc.
    [stream writeInt8:0]; // filler.
    
    {
        FMPSDStream *extraDataStream = [FMPSDStream PSDStreamForWritingToMemory];
        
        // Layer mask data. TABLE 1.18
        
        if (_mask) {
            [extraDataStream writeInt32:20];
            
            [extraDataStream writeInt32:_maskTop];
            [extraDataStream writeInt32:_maskLeft];
            [extraDataStream writeInt32:_maskBottom];
            [extraDataStream writeInt32:_maskRight];
            [extraDataStream writeInt8:255]; // lcolor
            [extraDataStream writeInt8:0]; // lflags
            [extraDataStream writeInt16:0];
        }
        else {
            [extraDataStream writeInt32:0];
        }
        
        // Layer blending ranges: See Table 1.19.
        [extraDataStream writeInt32:0];
        
#ifdef DEBUG
        long loc = [extraDataStream location];
#endif
        // Layer name: Pascal string, padded to a multiple of 4 bytes.
        [extraDataStream writePascalString:_layerName ? _layerName : @"" withPadding:4];
        
        FMAssert((([extraDataStream location] - loc) % 4) == 0); // padding has to be to 4!
        
        if (_isGroup) {
            [extraDataStream writeInt32:'8BIM'];
            [extraDataStream writeInt32:'lsct'];
            [extraDataStream writeInt32:12];
            [extraDataStream writeInt32:1];
            [extraDataStream writeInt32:'8BIM'];
            [extraDataStream writeInt32:'pass']; // blend mode!  AGAIN!
        }
        
        [extraDataStream writeInt32:'8BIM'];
        [extraDataStream writeInt32:'luni']; // unicode version of string.
        
        NSRange r = NSMakeRange(0, [_layerName length]);
        [extraDataStream writeInt32:(uint32_t)(r.length * 2) + 4]; // length of the next bit of data.
        
        // length of our data as a unicode string.
        [extraDataStream writeInt32:(uint32_t)r.length];
        
        unichar *buffer = malloc(sizeof(unichar) * ([_layerName length] + 1));
        
        [_layerName getCharacters:buffer range:r];
        buffer[([_layerName length])] = 0;
        
        for (NSUInteger i = 0; i < [_layerName length]; i++) {
            [extraDataStream writeInt16:buffer[i]];
        }
        
        free(buffer);
        
        [stream writeDataWithLengthHeader:[extraDataStream outputData]];
    }
}

- (uint32_t)writeChannels:(const uint8_t *const*)channels width:(uint16_t)width height:(uint16_t)height count:(int)count toStream:(FMPSDStream*)stream
{
    uint32_t totalLength = 0;
    uint16_t *lineLengths = malloc(sizeof(uint16_t) * count * height);
    size_t compressedLength = 0;
    for (int channel = 0; channel < count; ++channel) {
        for (int i = 0; i < height; ++i) {
            lineLengths[i + channel*height] = encodeRLE(channels[channel] + i * width, NULL, width);
            compressedLength += lineLengths[i + channel * height];
        }
    }
    size_t uncompressedLen = width * height * 4;
    if (uncompressedLen > compressedLength + sizeof(uint16_t) * height * count) {
        [stream writeInt16:1]; // RLE compression
        
        uint8_t *compressedBytes = malloc(compressedLength);
        
        uint8_t *ptr = compressedBytes;
        // Compress all of a planes in a single buffer
        for (int channel = 0; channel < count; ++channel) {
            for (int i = 0; i < height; ++i) {
                ptr += encodeRLE(channels[channel] + i * width, ptr, width);
            }
        }
        // Write all of the line lengths
        for (int channel = 0; channel < count; ++channel) {
            for (int i = 0; i < height; ++i) {
                [stream writeInt16:lineLengths[i + channel * height]];
            }
        }
        // Write the compressed data
        [stream writeChars:(char *)compressedBytes length:compressedLength];
        
        totalLength += compressedLength + 2 + 2*count*height;

        free(compressedBytes);
    } else {
        int len = width * height;
        [stream writeInt16:0]; // No compression
        for (int channel = 0; channel < count; ++channel) {
            [stream writeChars:(char *)channels[channel] length:len];
        }
        totalLength += len + 2;
    }
    free(lineLengths);
    
    return totalLength;
}

- (void)writeImageDataToStream:(FMPSDStream*)stream {
    if (_isGroup) {
        
        // zero for each channel.
        [stream writeInt16:0]; // -1
        [stream writeInt16:0]; // 0
        [stream writeInt16:0]; // 1
        [stream writeInt16:0]; // 2
        
        for (FMPSDLayer *layer in [[self layers] reverseObjectEnumerator]) {
            [layer writeImageDataToStream:stream];
        }
        
        // end folder crap.
        
        [stream writeInt16:0]; // -1
        [stream writeInt16:0]; // 0
        [stream writeInt16:0]; // 1
        [stream writeInt16:0]; // 2
        
        return;
    }
    
    if (!_width || !_height) {
        return;
    }
    
    uint8_t *r, *g, *b, *a, *m;
    [self getPlanesR:&r g:&g b:&b a:&a m:&m];

    if (_isComposite == NO) {
        // Handle each channel separately
        const int kChannelCount = 4;
        const uint8_t *channels[kChannelCount] = { (const uint8_t *)a, (const uint8_t *)r, (const uint8_t *)g, (const uint8_t *)b };
        uint32_t l = 0;
        for (int channel = 0; channel < kChannelCount; ++channel) {
            l += [self writeChannels:channels+channel width:_width height:_height count:1 toStream:stream];
        }
        // Odd-size padding
        if (l % 1) {
            [stream writeInt8:0];
        }
        if (m) {
            const int kChannelCount = 1;
            const uint8_t *channels[kChannelCount] = { m };
            l = [self writeChannels:channels width:_maskWidth height:_maskHeight count:kChannelCount toStream:stream];
            // Odd-size padding
            if (l % 1) {
                [stream writeInt8:0];
            }
        }
    } else {
        const int kChannelCount = 4;
        const uint8_t *channels[kChannelCount] = { (const uint8_t *)r, (const uint8_t *)g, (const uint8_t *)b, (const uint8_t *)a };
        [self writeChannels:channels width:_width height:_height count:kChannelCount toStream:stream];
    }
    free(r);
    free(g);
    free(b);
    free(a);
    free(m);
}

- (BOOL)readLayerInfo:(FMPSDStream*)stream error:(NSError**)err {
    uint32_t sig;
    
    BOOL success    = YES;
    
    _top            = [stream readSInt32];
    _left           = [stream readSInt32];
    _bottom         = [stream readSInt32];
    _right          = [stream readSInt32];
    
    _width          = _right - _left;
    _height         = _bottom - _top;
    
    _channels       = [stream readInt16];
    
    FMPSDDebug(@"  _top      %d", _top);
    FMPSDDebug(@"  _left     %d", _left);
    FMPSDDebug(@"  _bottom   %d", _bottom);
    FMPSDDebug(@"  _right    %d", _right);
    FMPSDDebug(@"  _width    %d", _width);
    FMPSDDebug(@"  _height   %d", _height);
    FMPSDDebug(@"  _channels %d", _channels);
    
    FMAssert(_channels <= 10);
    
    for (int chCount = 0; chCount < _channels; chCount++) {
        int16_t chandId = [stream readInt16];
        uint32_t chanLen = [stream readInt32];
        
        _channelIds[chCount]    = chandId;
        _channelLens[chCount]   = chanLen;
        
        FMPSDDebug(@"  Channel slot %d id: %d len: %d", chCount, chandId, chanLen);
    }
    
    
    
    FMPSDCheck8BIMSig(sig, stream, err);
    
    _blendMode = [stream readInt32];
    _opacity   = [stream readInt8];
    
    
    //debug(@"opacity: %d", _opacity);
    
    [stream readInt8]; // uint8_t clipping
    
    uint8_t flags = [stream readInt8];
    
    _transparencyProtected = flags & 0x01;
    _visible = ((flags >> 1) & 0x01) == 0;
    
    /*
     FMPSDDebug(@"  flags: %d", flags);
     FMPSDDebug(@"  _transparencyProtected: %d", _transparencyProtected);
     FMPSDDebug(@"  __visible:              %d", _visible);
     */
    
    // this guy does thing sa little differently...
    // file://localhost/Volumes/srv/Users/gus/Projects/acorn/plugin/samples/ACPSDLoader/libpsd/libpsd-0.9/src/layer_mask.c
    
    [stream readInt8]; // filler
    
    
    uint32_t lenOfExtraData     = [stream readInt32]; // 84454 - 2600 len
    //lenOfExtraData = (lenOfExtraData % 2 == 0) ? lenOfExtraData : lenOfExtraData + 1;
    //lenOfExtraData = (lenOfExtraData) & ~0x01;
    
    uint32_t foob = lenOfExtraData;
    foob = (foob % 2 == 0) ? foob : foob + 1;
    foob = (foob) & ~0x01;
    
    FMPSDDebug(@"lenOfExtraData: %d / %d", lenOfExtraData, foob);
    
#ifdef DEBUG
    long endLocation = [stream location] + lenOfExtraData;
#endif
    
    // layer mask / adjustment layer stuff.
    if (lenOfExtraData) {
        long startExtraLocation   = [stream location];
        
        // LAYER MASK / ADJUSTMENT LAYER DATA
		// Size of the data: 36, 20, or 0. If zero, the following fields are not
		// present
        
        uint32_t lenOfMask = [stream readInt32];
        
        FMPSDDebug(@"  lenOfMask:              %d", lenOfMask);
        
        if (lenOfMask) {
            _maskTop        = [stream readSInt32];
            _maskLeft       = [stream readSInt32];
            _maskBottom     = [stream readSInt32];
            _maskRight      = [stream readSInt32];
            
            
            uint8_t lcolor    = [stream readInt8];
            uint8_t lflags    = [stream readInt8];
            
            if (lenOfMask == 20) {
                [stream skipLength:2];
            }
            else if (lenOfMask == 28) { // yes, it can be 28
                // this image, created in cs5: http://blog.marshallbock.com/post/12040410577/iphone-4s-template
                [stream skipLength:10];
            }
            else {
                
                lflags = [stream readInt8]; // Real Flags. Same as Flags information above.
                lcolor = [stream readInt8]; // Real user mask background. 0 or 255.
                
                // and again. (Rectangle enclosing layer mask: Top, left, bottom, right.)
                // I think this might be for a vector mask?
                _maskTop2    = [stream readSInt32];
                _maskLeft2   = [stream readSInt32];
                _maskBottom2 = [stream readSInt32];
                _maskRight2  = [stream readSInt32];
                
            }
            
            (void)lcolor;
            (void)lflags;
            
            _maskWidth      = _maskRight - _maskLeft;
            _maskHeight     = _maskBottom - _maskTop;
            
            _maskWidth2      = _maskRight - _maskLeft;
            _maskHeight2     = _maskBottom - _maskTop;
        }
        
        FMPSDDebug(@" _maskWidth  %d", _maskWidth);
        FMPSDDebug(@" _maskHeight %d", _maskHeight);
        
        FMPSDDebug(@"location before blend read: %ld", [stream location]);
        
        // Layer blending ranges data
        uint32_t blendLength = [stream readInt32];
        
        // 83446
        if (blendLength == 65535) {
            FMAssert(NO);
        }
        
        FMPSDDebug(@"blendLength: %d", blendLength);
        if (blendLength) {
            FMPSDDebug(@"skipping %d bytes which is the blend length (at location %lld)", blendLength, [stream location]);
            [stream skipLength:blendLength];
        }
        
        
        // Layer name: Pascal string, padded to a multiple of 4 bytes.
        uint8_t psize = [stream readInt8];
        psize = ((psize + 1 + 3) & ~0x03) - 1;
        
        FMPSDDebug(@"Length of layer name is %d", psize);
        
        NSMutableData *d = [stream readDataOfLength:psize];
        [d increaseLengthBy:1];
        ((char*)[d mutableBytes])[psize] = 0;
        
        [self setLayerName:[NSString stringWithFormat:@"%s", [d mutableBytes]]];
        
        FMPSDDebug(@"Layer name is '%@'", _layerName);
        
        //_tags = [[NSMutableArray array] retain];
        
        while ([stream location] < startExtraLocation + lenOfExtraData) {
            
            FMPSDCheck8BIMSig(sig, stream, err);
            uint32_t tag  = [stream readInt32];
            uint32_t sigSize = [stream readInt32];
            
            // re sigSize: the official docs say "Length data below, rounded up to an even byte count."
            // but that's complete bullshit, as in the case of Adobe Fireworks CS3 spitting out bad data.
            // see "Theme Template for Photoshop.psd", originally from http://www.vanillasoap.com/2008/09/template-finder-co.html
            
            if (lenOfExtraData % 2 == 0) {
                sigSize = (sigSize) & ~0x01;
            }
            else {
                debug(@"ffffffffffffffffffffffffffffffffffffffffffffffffffff");
            }
            
            FMPSDDebug(@"NSFileTypeForHFSTypeCode(tag): %@:%d", FMPSDFileTypeForHFSTypeCode(tag), sigSize);
            
            if (tag == 'luni') { // layer name as unicode.
                [stream skipLength:sigSize];
            }
            else if (tag == 'lyid') { // layer id.
                _layerId = [stream readInt32];
                
                //debug(@"_layerId: %d", _layerId);
            }
            else if (tag == 'lsct') {
                
                //debug(@"size: %d", size);
                
                int type = [stream readInt32];
                
                if (sigSize == 12) {
                    FMPSDCheck8BIMSig(sig, stream, err);
                    _blendMode = [stream readInt32];
                    
                    //debug(@"xxxxxxxxx: %@", NSFileTypeForHFSTypeCode(_blendMode));
                    
                }
                /*
                 else {
                 FMAssert(sizeof(uint32_t) == sigSize);
                 }*/
                
                FMAssert(type < 4 && type >= 0);
                
                //debug(@"type: %d", type);
                
                switch (type) {
                    case 1:
                    case 2:
                        _dividerType = FMPSDLayerTypeFolder;
                        break;
                    case 3:
                        _dividerType = FMPSDLayerTypeHidden;
                        break;
                }
            }
            
            else if (tag == 'TySh') {
                // http://www.adobe.com/devnet-apps/photoshop/fileformatashtml/PhotoshopFileFormats.htm#50577409_19762
                long textStartLocation = [stream location];
                
                uint16_t version = [stream readInt16];
                if (version != 1) {
                    NSLog(@"Can't read the text data, we don't understand version %d!", version);
                    return NO;
                }
                
                CGAffineTransform t;
                
                t.a = [stream readDouble64];
                t.b = [stream readDouble64];
                t.c = [stream readDouble64];
                t.d = [stream readDouble64];
                t.tx = [stream readDouble64];
                t.ty = [stream readDouble64];
                
                uint16_t textVersion = [stream readInt16];
                [stream readInt32]; // descriptorVersion
                
                if (textVersion != 50) {
                    NSLog(@"Can't read the text data!");
                    return NO;
                }
                
                [self setTextDescriptor:[FMPSDDescriptor descriptorWithStream:stream psd:_psd]];
                
                uint16_t warpVersion = [stream readInt16];
                (void)warpVersion; // make the compiler happy about unused var
                FMAssert(warpVersion == 1);
                
                uint32_t descriptorVersion = [stream readInt32];
                (void)descriptorVersion; // make the compiler happy about unused var
                FMAssert(descriptorVersion == 16);
                
                [FMPSDDescriptor descriptorWithStream:stream psd:_psd];
                
                long currentLoc = [stream location];
                long delta = (textStartLocation + sigSize) - currentLoc;
                
                // supposidly we've got 24 bytes left for left, top, right, bottom - but that's bulshit.  There's nothing here but padding.
                [stream skipLength:delta];
                
                [self setIsText:YES];
                
            }
            else {
                [stream skipLength:sigSize];
            }
        }
        
        
        if (_dividerType == FMPSDLayerTypeHidden) {
            /*
             debug(@"_blendMode: %d", _blendMode);
             debug(@"NSFileTypeForHFSTypeCode: '%@'", NSFileTypeForHFSTypeCode(_blendMode));
             
             debug(@"_opacity: %d", _opacity);
             debug(@"_visible: %d", _visible);
             */
            
        }
    }
    
    //debug(@"endLocation: %ld vs %ld", endLocation, [stream location]);
    //debug(@"Done reading layer %@ - offset %ld", _layerName, [stream location]);
    
    FMAssert(endLocation == [stream location]); // the layer should end where we expect it to…
    
    return success;
}

static void decodeRLE(char *src, int sindex, int slen, char *dst, int dindex) {
    
    int max = sindex + slen;
    
    while (sindex < max) {
        char b = src[sindex++];
        
        int n = (int) b;
        if (n < 0) {
            n = 1 - n;
            b = src[sindex++];
            for (int i = 0; i < n; i++) {
                dst[dindex++] = b;
            }
        }
        else {
            n = n + 1;
            
            // arraycopy(Object src, int srcPos, Object dest, int destPos, int length)
            // Copies an array from the specified source array, beginning at the specified position, to the specified position of the destination array
            // System.arraycopy(src, sindex, dst, dindex, n);
            //memcpy((void *)dst[dindex], (void *)src[sindex], n);
            
            for (int x = 0; x < n; x++) {
                dst[dindex + x] = src[sindex + x];
            }
            
            dindex += n;
            sindex += n;
        }
    }
}



- (char*)parsePlaneCompressed:(FMPSDStream*)stream lineLengths:(uint16_t *)lineLengths planeNum:(int)planeNum isMask:(BOOL)isMask {
    
    //NSLog(@"location at parsePlaneCompressed: %ld for planeNum %d", [stream location], planeNum);
    
    uint32_t width = _width;
    uint32_t height = _height;
    
    
    if (isMask) {
        width = _maskWidth;
        height = _maskHeight;
        
        //debug(@"lineLengths: %d", lineLengths);
    }
    
    //debug(@"width: %d", width);
    //debug(@"height: %d", height);
    
    char *b = [[NSMutableData dataWithLength:sizeof(char) * (width * height)] mutableBytes];
    char *s = [[NSMutableData dataWithLength:sizeof(char) * (width * 2)] mutableBytes];
    
    //BOOL d = planeNum == 0;
    
    int pos = 0;
    int lineIndex = planeNum * height;
    for (uint32_t i = 0; i < height; i++) {
        uint16_t len = lineLengths[lineIndex++];
        
        //debug(@"%d: %d", i, len);
        
        FMAssert(!(len > (width * 2)));
        
        [stream readChars:(char*)s maxLength:len];
        
        decodeRLE(s, 0, len, b, pos);
        pos += width;
    }
    
    //NSLog(@"end location at parsePlaneCompressed: %ld for planeNum %d", [stream location], planeNum);
    
    return b;
}


- (char*)skipPlaneCompressed:(FMPSDStream*)stream lineLengths:(uint16_t *)lineLengths planeNum:(int)planeNum isMask:(BOOL)isMask {
    
    //NSLog(@"location at parsePlaneCompressed: %ld for planeNum %d", [stream location], planeNum);
    
    uint32_t width = _width;
    uint32_t height = _height;
    
    
    if (isMask) {
        width = _maskWidth;
        height = _maskHeight;
        
        //debug(@"lineLengths: %d", lineLengths);
    }
    
    
    int lineIndex = planeNum * height;
    for (uint32_t i = 0; i < height; i++) {
        uint16_t len = lineLengths[lineIndex++];
        
        //debug(@"%d: %d", i, len);
        
        FMAssert(!(len > (width * 2)));
        
        [stream skipLength:len];
    }
    
    //NSLog(@"end location at parsePlaneCompressed: %ld for planeNum %d", [stream location], planeNum);
    
    return 0;
}

- (char*)readPlaneFromStream:(FMPSDStream*)stream lineLengths:(uint16_t *)lineLengths needReadPlaneInfo:(BOOL)needReadPlaneInfo planeNum:(int)planeNum  error:(NSError**)err {
    
    //BOOL rawImageData           = NO;
    BOOL rleEncoded             = NO;
    //BOOL zipWithoutPrediction   = NO;
    //BOOL zipWithPrediction      = NO;
    
    //long startLoc = [stream location];
    
    //debug(@"planeNum: %d, needReadPlaneInfo? %d", planeNum, needReadPlaneInfo);
    
    uint32_t thisLength = _channelLens[planeNum];
    int16_t chanId     = _channelIds[planeNum];
    
    BOOL isMask       = (chanId == -2);
    
    if (needReadPlaneInfo) {
        uint16_t encoding = [stream readInt16];
        
        //debug(@"encoding: %d", encoding);
        //NSLog(@"_channelLens: %d", _channelLens[_channels]);
        
        thisLength -= 2;
        
        if (!thisLength) {
            //debug(@"empty, returning early");
            return 0x00;
        }
        
        if (encoding > 3) {
            
            NSLog(@"_layerName: '%@'", _layerName);
            NSLog(@"_channels: %d", _channels);
            NSLog(@"_channelLens: %d", _channelLens[_channels]);
            NSLog(@"planeNum: %d", planeNum);
            
            NSString *s = [NSString stringWithFormat:@"%s:%d Bad encoding (%d) at offset %ld", __FUNCTION__, __LINE__, encoding, [stream location]];
            
            if (err) {
                *err = [NSError errorWithDomain:@"com.flyingmeat.FMPSD" code:3 userInfo:[NSDictionary dictionaryWithObject:s forKey:NSLocalizedDescriptionKey]];
            }
            
            return NO;
        }
        
        //rawImageData         = (encoding == 0);
        rleEncoded           = (encoding == 1);
        //zipWithPrediction    = (encoding == 2);
        //zipWithoutPrediction = (encoding == 3);
        
        //debug(@"rleEncoded: %d", rleEncoded);
        //debug(@"lineLengths: %d", (int)lineLengths);
        
        if (rleEncoded) {
            if (lineLengths == nil) {
                
                int32_t h = (isMask ? _maskHeight : _height);
                
                lineLengths = [[NSMutableData dataWithLength:sizeof(uint16_t) * h] mutableBytes];
                
                //debug(@"(isMask ? _maskHeight : _height): %d", h);
                
                for (int i = 0; i < h; i++) {
                    lineLengths[i] = [stream readInt16];
                    //debug(@"lineLengths[%d]: %d %ld", i, lineLengths[i], [stream location]);
                }
            }
        }
        planeNum = 0;
    }
    else {
        rleEncoded = lineLengths != nil;
    }
    
    //debug(@"rleEncoded: %d", rleEncoded);
    
    char *ret = nil;
    
    if (rleEncoded) {
        ret = (char*)[self parsePlaneCompressed:stream lineLengths:lineLengths planeNum:planeNum isMask:isMask];
    }
    else {
        uint32_t size = _width * _height;
        
        if (isMask) {
            FMAssert(_maskWidth > 0);
            FMAssert(_maskHeight > 0);
            size = _maskWidth * _maskHeight;
        }
        
        NSMutableData *d = [stream readDataOfLength:size];
        ret = [d mutableBytes];
        
        FMAssert([d length] == size);
        
    }
    
    
    return ret;
}

- (char*)skipPlaneFromStream:(FMPSDStream*)stream lineLengths:(uint16_t *)lineLengths needReadPlaneInfo:(BOOL)needReadPlaneInfo planeNum:(int)planeNum  error:(NSError**)err {
    
    //BOOL rawImageData           = NO;
    BOOL rleEncoded             = NO;
    //BOOL zipWithoutPrediction   = NO;
    //BOOL zipWithPrediction      = NO;
    
    //long startLoc = [stream location];
    
    //debug(@"planeNum: %d, needReadPlaneInfo? %d", planeNum, needReadPlaneInfo);
    
    uint32_t thisLength = _channelLens[planeNum];
    int16_t chanId     = _channelIds[planeNum];
    
    BOOL isMask       = (chanId == -2);
    
    if (needReadPlaneInfo) {
        uint16_t encoding = [stream readInt16];
        
        //debug(@"encoding: %d", encoding);
        //NSLog(@"_channelLens: %d", _channelLens[_channels]);
        
        thisLength -= 2;
        
        if (!thisLength) {
            //debug(@"empty, returning early");
            return 0x00;
        }
        
        if (encoding > 3) {
            
            NSLog(@"_layerName: '%@'", _layerName);
            NSLog(@"_channels: %d", _channels);
            NSLog(@"_channelLens: %d", _channelLens[_channels]);
            NSLog(@"planeNum: %d", planeNum);
            
            NSString *s = [NSString stringWithFormat:@"%s:%d Bad encoding (%d) at offset %ld", __FUNCTION__, __LINE__, encoding, [stream location]];
            
            if (err) {
                *err = [NSError errorWithDomain:@"com.flyingmeat.FMPSD" code:3 userInfo:[NSDictionary dictionaryWithObject:s forKey:NSLocalizedDescriptionKey]];
            }
            
            return NO;
        }
        
        //rawImageData         = (encoding == 0);
        rleEncoded           = (encoding == 1);
        //zipWithPrediction    = (encoding == 2);
        //zipWithoutPrediction = (encoding == 3);
        
        //debug(@"rleEncoded: %d", rleEncoded);
        //debug(@"lineLengths: %d", (int)lineLengths);
        
        if (rleEncoded) {
            if (lineLengths == nil) {
                
                int32_t h = (isMask ? _maskHeight : _height);
                
                lineLengths = [[NSMutableData dataWithLength:sizeof(uint16_t) * h] mutableBytes];
                
                //debug(@"(isMask ? _maskHeight : _height): %d", h);
                
                for (int i = 0; i < h; i++) {
                    lineLengths[i] = [stream readInt16];
                    //debug(@"lineLengths[%d]: %d %ld", i, lineLengths[i], [stream location]);
                }
            }
        }
        planeNum = 0;
    }
    else {
        rleEncoded = lineLengths != nil;
    }
    
    //debug(@"rleEncoded: %d", rleEncoded);
    
    char *ret = nil;
    
    if (rleEncoded) {
        ret = (char*)[self skipPlaneCompressed:stream lineLengths:lineLengths planeNum:planeNum isMask:isMask];
    }
    
    return ret;
}

- (int)channelIdForRow:(int)row {
    return _channelIds[row];
}

- (CGImageRef)readImage
{
    CGImageRef image = NULL;
    @autoreleasepool {
        FMPSDStream *stream = _stream;
        if (stream == nil) {
            return NULL;
        }
        long oldLoc = [stream location];
        [stream seek:_imageOffset];
        
        uint16_t *lineLengths = NULL;
        if (_imageRLE) {
            uint32_t nLines = _height * _channels;
            lineLengths = malloc(sizeof(uint16_t) * nLines);
            [stream seek:_imageOffset-sizeof(uint16_t) * nLines];
            for (uint32_t i = 0; i < nLines; i++) {
                lineLengths[i] = [stream readInt16];
            }
        }
        BOOL needsPlaneInfo = _needsPlaneInfo;
        NSError *e = nil;
        
        char* r = nil, *g = nil, *b = nil, *a = nil, *m = nil;
        
        int j = 0;
        
        for (; j < _channels; j++) {
            
            int channelId = [self channelIdForRow:j];
            
            FMPSDDebug(@"Reading row %d, channel id %d for %@ lineLengths ? %d pos %ld _channelLens[j]: %d", j, channelId, _layerName, (lineLengths != nil), [stream location], _channelLens[j]);
            
            if (channelId == -1) { // alpha
                FMPSDDebug(@"reading alpha");
                a = [self readPlaneFromStream:stream lineLengths:lineLengths needReadPlaneInfo:needsPlaneInfo planeNum:j error:&e];
            }
            else if (channelId == 0) { // r
                FMPSDDebug(@"reading red");
                r = [self readPlaneFromStream:stream lineLengths:lineLengths needReadPlaneInfo:needsPlaneInfo planeNum:j error:&e];
            }
            else if (channelId == 1) { // g
                FMPSDDebug(@"reading green");
                g = [self readPlaneFromStream:stream lineLengths:lineLengths needReadPlaneInfo:needsPlaneInfo planeNum:j error:&e];
            }
            else if (channelId == 2) { // b
                FMPSDDebug(@"reading blue");
                b = [self readPlaneFromStream:stream lineLengths:lineLengths needReadPlaneInfo:needsPlaneInfo planeNum:j error:&e];
            }
            else if (channelId == -2) { // m
                FMPSDDebug(@"reading mask");
                
                long start = [stream location];
                
                long end = _channelLens[j] + start;
                
                m = [self readPlaneFromStream:stream lineLengths:lineLengths needReadPlaneInfo:needsPlaneInfo planeNum:j error:&e];
                
                if (!m) {
                    debug(@"whoa- m is empty!");
                }
                
                long diff = end - [stream location];
                
                [stream skipLength:diff];
                
                /*
                 if (diff != 0) {
                 
                 NSLog(@"expected to read %d bytes, only read %ld (%ld diff)", _channelLens[j], ([stream location] - start), diff);
                 
                 NSString *s = [NSString stringWithFormat:@"%s:%d Mask ended unexpededly at offset %ld", __FUNCTION__, __LINE__, [stream location]];
                 NSLog(@"%@", s);
                 if (err) {
                 *err = [NSError errorWithDomain:@"com.flyingmeat.FMPSD" code:2 userInfo:[NSDictionary dictionaryWithObject:s forKey:NSLocalizedDescriptionKey]];
                 }
                 
                 return NO;
                 }
                 */
            }
            else {
                [stream skipLength:_channelLens[j]];
            }
        }
        if (lineLengths) {
            free(lineLengths);
            lineLengths = NULL;
        }
        if ((_height <= 0) || (_width <= 0)) {
            return NULL;
        }
        
        if (!r) {
            r = [[NSMutableData dataWithLength:sizeof(unsigned char) * _width * _height] mutableBytes];
        }
        
        if (!g) {
            g = [[NSMutableData dataWithLength:sizeof(unsigned char) * _width * _height] mutableBytes];
        }
        
        if (!b) {
            b = [[NSMutableData dataWithLength:sizeof(unsigned char) * _width * _height] mutableBytes];
        }
        
        if (!a) {
            a = [[NSMutableData dataWithLength:sizeof(unsigned char) * _width * _height] mutableBytes];
            memset(a, 255, _width * _height);
        }
        
        
        size_t n = _width * _height;
        
        if (n) {
            
            CGContextRef ctx = CGBitmapContextCreate(nil, _width, _height, 8, _width * 4, [_psd colorSpace], kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
            
            FMPSDPixel *c = CGBitmapContextGetData(ctx);
            
            
            // OK, we're going to de-plane our image, and premultiply it as well.
            dispatch_queue_t queue = dispatch_get_global_queue(0, DISPATCH_QUEUE_PRIORITY_HIGH);
            
            dispatch_apply(_height, queue, ^(size_t row) {
                
                FMPSDPixel *p = &c[_width * row];
                
                size_t planeStart = (row * _width);
                int32_t x = 0;
                while (x < _width) {
                    
                    size_t planeLoc = planeStart + x;
                    
                    FMPSDPixelCo ac = a[planeLoc];
                    FMPSDPixelCo rc = r[planeLoc];
                    FMPSDPixelCo gc = g[planeLoc];
                    FMPSDPixelCo bc = b[planeLoc];
                    
                    p->a = ac;
                    
                    p->r = (rc * ac + 127) / 255;
                    p->g = (gc * ac + 127) / 255;
                    p->b = (bc * ac + 127) / 255;
                    
                    p++;
                    x++;
                }
            });
            
            image = CGBitmapContextCreateImage(ctx);
            
            CGContextRelease(ctx);
            
            if (m) {
#if TARGET_OS_IPHONE
                CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
#else
                CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceGenericGray);
#endif
                
                CGContextRef alphaMask = CGBitmapContextCreate(m, _maskWidth, _maskHeight, 8, _maskWidth, cs, (CGBitmapInfo)kCGImageAlphaNone);
                
                //            _mask = CGBitmapContextCreateImage(alphaMask);
                
                CGColorSpaceRelease(cs);
                CGContextRelease(alphaMask);
                
            }
        }
        [stream seek:oldLoc];
    }
    return (CGImageRef)CFAutorelease(image);
}

- (BOOL)readImageDataFromStream:(FMPSDStream*)stream lineLengths:(uint16_t *)lineLengths needReadPlanInfo:(BOOL)needsPlaneInfo error:(NSError**)err {
    @autoreleasepool {
        _imageOffset = stream.location;
        _needsPlaneInfo = needsPlaneInfo;
        if (_stream != stream) {
            _stream = stream;
        }
        _imageRLE = lineLengths != NULL;

        int j = 0;
        
        for (; j < _channels; j++) {
            
            int channelId = [self channelIdForRow:j];
            
            FMPSDDebug(@"Reading row %d, channel id %d for %@ lineLengths ? %d pos %ld _channelLens[j]: %d", j, channelId, _layerName, (lineLengths != nil), [stream location], _channelLens[j]);
            
            if (channelId == -1) { // alpha
                FMPSDDebug(@"reading alpha");
                @autoreleasepool {
                    [self readPlaneFromStream:stream lineLengths:lineLengths needReadPlaneInfo:needsPlaneInfo planeNum:j error:err];
                }
            }
            else if (channelId == 0) { // r
                FMPSDDebug(@"reading red");
                @autoreleasepool {
                    [self readPlaneFromStream:stream lineLengths:lineLengths needReadPlaneInfo:needsPlaneInfo planeNum:j error:err];
                }
            }
            else if (channelId == 1) { // g
                FMPSDDebug(@"reading green");
                @autoreleasepool {
                    [self readPlaneFromStream:stream lineLengths:lineLengths needReadPlaneInfo:needsPlaneInfo planeNum:j error:err];
                }
            }
            else if (channelId == 2) { // b
                FMPSDDebug(@"reading blue");
                @autoreleasepool {
                    [self readPlaneFromStream:stream lineLengths:lineLengths needReadPlaneInfo:needsPlaneInfo planeNum:j error:err];
                }
            }
            else if (channelId == -2) { // m
                FMPSDDebug(@"reading mask");
                
                long start = [stream location];
                
                long end = _channelLens[j] + start;
                @autoreleasepool {
                    [self readPlaneFromStream:stream lineLengths:lineLengths needReadPlaneInfo:needsPlaneInfo planeNum:j error:err];
                }
                
                long diff = end - [stream location];
                
                [stream skipLength:diff];
                
                /*
                 if (diff != 0) {
                 
                 NSLog(@"expected to read %d bytes, only read %ld (%ld diff)", _channelLens[j], ([stream location] - start), diff);
                 
                 NSString *s = [NSString stringWithFormat:@"%s:%d Mask ended unexpededly at offset %ld", __FUNCTION__, __LINE__, [stream location]];
                 NSLog(@"%@", s);
                 if (err) {
                 *err = [NSError errorWithDomain:@"com.flyingmeat.FMPSD" code:2 userInfo:[NSDictionary dictionaryWithObject:s forKey:NSLocalizedDescriptionKey]];
                 }
                 
                 return NO;
                 }
                 */
            }
            else {
                [stream skipLength:_channelLens[j]];
            }
        }
        
        if ((_height <= 0) || (_width <= 0)) {
            return YES;
        }
    }
    return YES;
}


- (CGImageRef)mask {
    return _mask;
}

- (void)setMask:(CGImageRef)anImage {
    
    if (anImage) {
        CGImageRetain(anImage);
        _maskWidth = (uint32_t)CGImageGetWidth(anImage);
        _maskHeight = (uint32_t)CGImageGetHeight(anImage);
    }
    
    if (_mask) {
        CGImageRelease(_mask);
    }
    
    _mask = anImage;
}



- (CGImageRef)image {
    CGImageRef image = _image;
    if (image == NULL) {
        image = [self readImage];
    }
    return image;
}

- (void)setImage:(CGImageRef)anImage {
    
    if (anImage) {
        CGImageRetain(anImage);
    }
    
    if (_image) {
        CGImageRelease(_image);
    }
    
    _image = anImage;
    
}

- (void)addLayerToGroup:(FMPSDLayer*)layer {
    if (!_layers) {
        _layers = [NSMutableArray array];
    }
    
    [_layers addObject:layer];
}

- (CGRect)frame {
    return CGRectMake(_left, (float)[_psd height] - (float)_bottom, _width, _height);
}

- (void)setFrame:(CGRect)frame {
    
    // the origin is in the top left.
    
    CGFloat psdHeight   = [_psd height];
    
    _width              = frame.size.width;
    _height             = frame.size.height;
    
    _left               = CGRectGetMinX(frame);
    _right              = CGRectGetMaxX(frame);
    
    _top                = psdHeight - CGRectGetMaxY(frame);
    _bottom             = psdHeight - CGRectGetMinY(frame);
}

- (CGRect)maskFrame {
    return CGRectMake(_maskLeft, (float)[_psd height] - (float)_maskBottom, _maskWidth, _maskHeight);
}

- (void)setMaskFrame:(CGRect)frame {
    CGFloat psdHeight   = [_psd height];
    
    _maskWidth  = frame.size.width;
    _maskHeight = frame.size.height;
    
    _maskLeft   = CGRectGetMinX(frame);
    _maskRight  = CGRectGetMaxX(frame);
    
    _maskTop    = psdHeight - CGRectGetMaxY(frame);
    _maskBottom = psdHeight - CGRectGetMinY(frame);
}


- (CIImage*)CIImageForComposite {
    
    //debug(@"compositeCIImage: %@", _layerName);
    
    @autoreleasepool {
        if (!_visible) {
            return [CIImage emptyImage];
        }
        
        if (_isGroup) {
            
            CIImage *i = [[CIImage emptyImage] imageByCroppingToRect:CGRectMake(0, 0, [_psd width], [_psd height])];
            
            for (FMPSDLayer *layer in [_layers reverseObjectEnumerator]) {
                
                if ([layer visible]) {
                    
                    CIFilter *sourceOver = [CIFilter filterWithName:@"CISourceOverCompositing"];
                    CIImage *layerImage = [layer CIImageForComposite];
                    [sourceOver setValue:layerImage forKey:kCIInputImageKey];
                    [sourceOver setValue:i forKey:kCIInputBackgroundImageKey];
                    
                    i = [sourceOver valueForKey:kCIOutputImageKey];
                }
                
            }
            
            return i;
        }
        
        
        CIImage *img = nil;
        CGImageRef image = _image;
        if (image == NULL && _imageOffset) {
            image = [self readImage];
        }
        if (image == NULL && self.psd.delegate) {
            image = [self.psd.delegate imageForLayer:self];
        }
        if (!image) {
            img = [[CIImage emptyImage] imageByCroppingToRect:CGRectMake(0, 0, _width, _height)];
        }
        else {
            img = [CIImage imageWithCGImage:image];
        }
        
        
        CGRect r = [self frame];
        img = [img imageByApplyingTransform:CGAffineTransformMakeTranslation(r.origin.x, r.origin.y)];
        
        if (_opacity < 255) {
            
            FMPSDAlphaFilter *f = [[FMPSDAlphaFilter alloc] init];
            
            [f setValue:img forKey:kCIInputImageKey];
            [f setAlpha:[NSNumber numberWithFloat:_opacity / 255.f]];
            
            img = [f valueForKey:kCIOutputImageKey];
        }
        
        if (_mask) {
            
            CIImage *maskImage = [CIImage imageWithCGImage:_mask];
            CGRect maskFrame = [self maskFrame];
            maskImage = [maskImage imageByApplyingTransform:CGAffineTransformMakeTranslation(maskFrame.origin.x, maskFrame.origin.y)];
            
            CIFilter *filter = [CIFilter filterWithName:@"CIColorInvert"];
            [filter setValue:maskImage forKey:@"inputImage"];
            maskImage = [filter valueForKey: @"outputImage"];
            
            
            CIFilter *blendFilter       = [CIFilter filterWithName:@"CIBlendWithMask"];
            
            [blendFilter setValue:[CIImage emptyImage] forKey:@"inputImage"];
            [blendFilter setValue:img forKey:@"inputBackgroundImage"];
            [blendFilter setValue:maskImage forKey:@"inputMaskImage"];
            
            
            
            img = [blendFilter valueForKey:kCIOutputImageKey];
        }
        return img;
    }
}

- (void)writeToFileAsPSD:(NSString *)path {
    
	CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], (CFStringRef)@"com.adobe.photoshop-image", 1, NULL);
	CGImageDestinationAddImage(destination, [self image], (__bridge CFDictionaryRef)[NSDictionary dictionary]);
	CGImageDestinationFinalize(destination);
    CFRelease(destination);
}

- (void)printTree:(NSString*)spacing {
    
    NSLog(@"%@%@%@", spacing, _isGroup ? @"+" : @"*", _layerName);
    
    spacing = [spacing stringByAppendingString:@"  "];
    
    for (FMPSDLayer *layer in _layers) {
        [layer printTree:spacing];
    }
}

- (NSInteger)countOfSubLayers {
    
    NSInteger count = 0;
    
    for (FMPSDLayer *layer in _layers) {
        
        count++;
        
        if ([layer isGroup]) {
            count += [layer countOfSubLayers];
            count ++; // division layer
        }
    }
    
    return count;
}

- (void)setupChannelIdsForCompositeRead {
    _channelIds[0] = 0;
    _channelIds[1] = 1;
    _channelIds[2] = 2;
    _channelIds[3] = -1;
}

@end
