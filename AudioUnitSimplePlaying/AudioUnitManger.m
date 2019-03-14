//
//  AudioUnitManger.m
//  AudioUnitSimplePlaying
//
//  Created by Double-J🍎 on 2019/3/14.
//  Copyright © 2019年 Double-J🍎. All rights reserved.
//

#import "AudioUnitManger.h"
#import <AudioToolbox/AudioToolbox.h>
@interface AudioUnitManger()<NSURLSessionDelegate>
{
    NSInteger _readedPacketIndex;
    UInt32 _renderBufferSize;
    
    AudioUnit _outAudioUinit;
    AudioStreamBasicDescription _streamDescription;
    AudioFileStreamID _audioFileStreamID;
    AudioBufferList *_renderBufferList;
    AudioConverterRef _converter;
}
@property(nonatomic,strong) NSMutableArray<NSData*> *paketsArray;
@end
@implementation AudioUnitManger

//调用AudioConverterFillComplexBuffer传入数据，并在callBack函数调用填充buffer的方法。
OSStatus  DJAURenderCallback(void *inRefCon,AudioUnitRenderActionFlags *    ioActionFlags,const AudioTimeStamp *inTimeStamp,UInt32    inBusNumber,UInt32 inNumberFrames, AudioBufferList * __nullable ioData){
    AudioUnitManger *self = (__bridge AudioUnitManger *)(inRefCon);
    @synchronized (self) {
        if (self->_readedPacketIndex < self.paketsArray.count) {
            @autoreleasepool {
                UInt32 packetSize = inNumberFrames;
                OSStatus status = AudioConverterFillComplexBuffer(self->_converter, DJAudioConverterComplexInputDataProc, (__bridge void *)self, &packetSize, self->_renderBufferList, NULL);
                if (status != noErr && status != 'DJnd') {
                    [self stop];
                    return -1;
                }
                else if (!packetSize) {
                    ioData->mNumberBuffers = 0;
                }
                else {
                    ioData->mNumberBuffers = 1;
                    ioData->mBuffers[0].mNumberChannels = 2;
                    ioData->mBuffers[0].mDataByteSize = self->_renderBufferList->mBuffers[0].mDataByteSize;
                    ioData->mBuffers[0].mData =self->_renderBufferList->mBuffers[0].mData;
                    self->_renderBufferList->mBuffers[0].mDataByteSize = self->_renderBufferSize;
                }
            }
        }
        else {
            ioData->mNumberBuffers = 0;
            return -1;
        }
    }
    return noErr;
    
}
//歌曲信息解析回调将传递给回调的常量。
//每当在数据中分析属性的值时，都将回调
void DJAudioFileStream_PropertyListenerProc(void *    inClientData,AudioFileStreamID                inAudioFileStream,AudioFileStreamPropertyID    inPropertyID,AudioFileStreamPropertyFlags *    ioFlags)
{
    if (inPropertyID == kAudioFileStreamProperty_DataFormat) {
        
        AudioUnitManger *self = (__bridge AudioUnitManger *)(inClientData);
        UInt32 dataSize = 0;
        Boolean writable = false;
        OSStatus status = AudioFileStreamGetPropertyInfo(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &dataSize, &writable);
        assert(status == noErr);
        
        status = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &dataSize, &self->_streamDescription);
        assert(status == noErr);
        AudioStreamBasicDescription destFormat = audioStreamBasicDescription();
        status = AudioConverterNew(&self->_streamDescription, &destFormat, &self->_converter);
        assert(status == noErr);
    }
    
}
//解析分离帧回调
//每当在数据中分析数据包时，都会向客户机传递指向数据包的指针。开始回调。
void DJAudioFileStreamPacketsProc(void *inClientData,UInt32 inNumberBytes,UInt32                            inNumberPackets,const void *inInputData,AudioStreamPacketDescription *inPacketDescriptions)
{
    AudioUnitManger *self = (__bridge AudioUnitManger *)(inClientData);
    if (inPacketDescriptions) {
        for (int i = 0; i < inNumberPackets; i++) {
            SInt64 packetOffset = inPacketDescriptions[i].mStartOffset;
            UInt32 packetSize = inPacketDescriptions[i].mDataByteSize;
            assert(packetSize > 0);
            NSData *packet = [NSData dataWithBytes:inInputData + packetOffset length:packetSize];
            [self.paketsArray addObject:packet];
        }
    }
    if (self->_readedPacketIndex == 0 && self.paketsArray.count > [self packetsPerSecond] * 3) {
        [self play];
        
    }
}

- (double)packetsPerSecond
{
    if (!(_streamDescription.mFramesPerPacket > 0)) {
        return 0;
    }
    return _streamDescription.mSampleRate / _streamDescription.mFramesPerPacket;
}
/*
 AudioFileStreamOpen (
 void * __nullable                        inClientData,
 AudioFileStream_PropertyListenerProc    inPropertyListenerProc,
 AudioFileStream_PacketsProc                inPacketsProc,
 AudioFileTypeID                            inFileTypeHint,
 AudioFileStreamID __nullable * __nonnull outAudioFileStream)
 向解析器提供数据,当在数据中发现有内容（如属性和音频包)回调
 @参数包数据 inClientData
 @参数infiletypehint
 对于无法根据数据轻松或唯一确定其类型的文件（ADTS、AC3），
 此提示可用于指示文件类型。
 否则，如果您不知道文件类型，则可以传递零。
 @参数outaudiofilestream
 用于其他audiofilestream api调用的新文件流ID。
 */
//inClientData 上下文对象
//AudioFileStream_PropertyListenerProc 歌曲信息解析的回调，每次解析出一个歌曲信息，都会执行一次回调。
//AudioFileStream_PacketsProc 分离帧的回调，每解析出一部分帧就会进行一次回调
//AudioFileTypeID 是文件类型的提示，创建指定文件格式的音频流解析器。

-(instancetype)initWithURL:(NSURL*)url
{
    if (self = [super init]) {
        _paketsArray = [NSMutableArray arrayWithCapacity:0];
        [self setupOutAudioUnit];
        AudioFileStreamOpen((__bridge void * _Nullable)(self), DJAudioFileStream_PropertyListenerProc, DJAudioFileStreamPacketsProc, 0, &_audioFileStreamID);
        NSURLSession *urlSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:nil];
        NSURLSessionDataTask *task = [urlSession dataTaskWithURL:url];
        [task resume];
    }
    return self;
}
-(void)setupOutAudioUnit
{
    //    构造RemoteIO类型的AudioUnit描述的结构体
    AudioComponentDescription ioUnitDescription;
    memset(&ioUnitDescription, 0, sizeof(AudioComponentDescription));
    ioUnitDescription.componentType = kAudioUnitType_Output;
    ioUnitDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    ioUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    ioUnitDescription.componentFlags = 0;
    ioUnitDescription.componentFlagsMask = 0;
    
    //    首先根据AudioUnit的描述，找出实际的AudioUnit类型：
    AudioComponent outComponent = AudioComponentFindNext(NULL, &ioUnitDescription);
    //    根据AudioUnit类型创建出这个AudioUnit实例：
    OSStatus status = AudioComponentInstanceNew(outComponent, &_outAudioUinit);
    assert(status == noErr);
    //  Audio Stream Format的描述,构造BasicDescription结构体
    AudioStreamBasicDescription pcmStreamDesc = audioStreamBasicDescription();
    
    OSStatus statusSetProperty = noErr;
    //   将这个结构体设置给对应的AudioUnit,将这Unit的Element0的Out-putScope和Speaker进行连接使用扬声器
    statusSetProperty = AudioUnitSetProperty(_outAudioUinit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &pcmStreamDesc, sizeof(pcmStreamDesc));
    //    AudioUnitSetProperty(AudioUnit                inUnit,
    //                         AudioUnitPropertyID        inID,
    //                         AudioUnitScope            inScope,
    //                         AudioUnitElement        inElement,
    //                         const void * __nullable    inData,
    //                         UInt32                    inDataSize)
    //    构造一个AURenderCallback的结构体，并指定一个回调函数，然后设置给RemoteIO Unit的输入端，当RemoteIO Unit需要数据输入的时候就会回调该回调函数
    AURenderCallbackStruct callBackStruct;
    callBackStruct.inputProc = DJAURenderCallback;
    callBackStruct.inputProcRefCon = (__bridge void * _Nullable)(self);
    
    AudioUnitSetProperty(_outAudioUinit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &callBackStruct, sizeof(AURenderCallbackStruct));
    
    UInt32 bufferSize = 4096 * 4;
    _renderBufferSize = bufferSize;
    _renderBufferList = calloc(4, sizeof(UInt32)+sizeof(bufferSize));
    _renderBufferList->mNumberBuffers = 1;
    _renderBufferList->mBuffers[0].mData = calloc(1, bufferSize);
    _renderBufferList->mBuffers[0].mDataByteSize = bufferSize;
    _renderBufferList->mBuffers[0].mNumberChannels = 2;
    
}

static AudioStreamBasicDescription audioStreamBasicDescription()
{
    AudioStreamBasicDescription description;
    description.mSampleRate = 44100.0;
    description.mFormatID = kAudioFormatLinearPCM;
    description.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger;
    description.mFramesPerPacket = 1;
    description.mBytesPerPacket = 4;
    description.mBytesPerFrame = 4;
    description.mChannelsPerFrame = 2;
    description.mBitsPerChannel = 16;
    description.mReserved = 0;
    //    msamplerate:流中每秒数据的采样帧数。
    //    mformatid：在流中指定常规音频数据格式的标识符。（KaudioFormilanePCM等）
    //    mFormatflags：格式化特定标志以指定格式的详细信息。（klinearpcmFormatflagIsignedInteger、klinearpcmFormatflagIsFloat、klinearpcmFormatflagIsBigEndian、klinearpcmFormatflagIsPackaged、klinearpcmFormatflagIsOnInterleaved等）
    //    mbytesperpacket：数据包中的字节数。
    //    mframesPerpacket：每个数据包中的样本帧数。
    //    mbytespeframe：单个数据采样帧中的字节数。
    //    mchannelsPerFrame：每帧数据中的通道数
    //    mbitsPerchannel：数据帧中每个通道的采样数据位数。
    //    mReserved将结构垫出以强制8字节对齐
    return description;
}

OSStatus DJAudioConverterComplexInputDataProc(AudioConverterRef inAudioConverter,UInt32 * ioNumberDataPackets,AudioBufferList *  ioData,AudioStreamPacketDescription * __nullable * __nullable outDataPacketDescription,void * __nullable inUserData)
{
    AudioUnitManger *self = (__bridge AudioUnitManger *)(inUserData);
    if (self->_readedPacketIndex >= self.paketsArray.count) {
        NSLog(@"Have No Data");
        return -1;
    }
    
    //    填充PCM到缓冲区
    NSData *packet = self.paketsArray[self->_readedPacketIndex];
    ioData->mNumberBuffers = 1;
    ioData->mBuffers[0].mData = (void *)packet.bytes;
    ioData->mBuffers[0].mDataByteSize = (UInt32)packet.length;
    
    static AudioStreamPacketDescription aspdesc;
    aspdesc.mDataByteSize = (UInt32)packet.length;
    aspdesc.mStartOffset = 0;
    aspdesc.mVariableFramesInPacket = 1;
    *outDataPacketDescription = &aspdesc;
    self->_readedPacketIndex++;
    return 0;
    
}

#pragma mark -NSURLSessionDelegate
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    OSStatus status = AudioFileStreamParseBytes(_audioFileStreamID, (UInt32)data.length, data.bytes, 0);
    if (status == noErr) {
        
    }
}

- (BOOL)play
{
    OSStatus status = AudioOutputUnitStart(_outAudioUinit);
    if (status == noErr) {
        return YES;
    }
    return 0;
}

- (BOOL)stop
{
    OSStatus status = AudioOutputUnitStop(_outAudioUinit);
    if (status == noErr) {
        return YES;
    }
    return 0;
}
@end

