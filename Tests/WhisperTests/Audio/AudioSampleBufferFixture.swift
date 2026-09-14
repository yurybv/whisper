import AudioToolbox
@preconcurrency import CoreMedia
import XCTest

func makeTestAudioSampleBuffer(
    presentationSeconds: Double,
    amplitude: Float,
    frameCount: Int = 4_800
) throws -> CMSampleBuffer {
    let sampleRate: Double = 48_000
    var description = AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
        mFramesPerPacket: 1,
        mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
        mChannelsPerFrame: 1,
        mBitsPerChannel: 32,
        mReserved: 0
    )
    var formatDescription: CMAudioFormatDescription?
    guard CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: &description,
        layoutSize: 0,
        layout: nil,
        magicCookieSize: 0,
        magicCookie: nil,
        extensions: nil,
        formatDescriptionOut: &formatDescription
    ) == noErr else {
        throw AudioSampleBufferFixtureError.cannotCreateFormat
    }

    var samples = Array(repeating: amplitude, count: frameCount)
    var blockBuffer: CMBlockBuffer?
    let byteCount = samples.count * MemoryLayout<Float>.size
    guard CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: byteCount,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: byteCount,
        flags: 0,
        blockBufferOut: &blockBuffer
    ) == kCMBlockBufferNoErr, let blockBuffer else {
        throw AudioSampleBufferFixtureError.cannotCreateData
    }
    let copyStatus = samples.withUnsafeMutableBytes { bytes in
        CMBlockBufferReplaceDataBytes(
            with: bytes.baseAddress!,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: byteCount
        )
    }
    guard copyStatus == kCMBlockBufferNoErr else {
        throw AudioSampleBufferFixtureError.cannotCreateData
    }

    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
        presentationTimeStamp: CMTime(seconds: presentationSeconds, preferredTimescale: 48_000),
        decodeTimeStamp: .invalid
    )
    var sampleSize = MemoryLayout<Float>.size
    var sampleBuffer: CMSampleBuffer?
    guard CMSampleBufferCreate(
        allocator: kCFAllocatorDefault,
        dataBuffer: blockBuffer,
        dataReady: true,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: formatDescription,
        sampleCount: frameCount,
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timing,
        sampleSizeEntryCount: 1,
        sampleSizeArray: &sampleSize,
        sampleBufferOut: &sampleBuffer
    ) == noErr, let sampleBuffer else {
        throw AudioSampleBufferFixtureError.cannotCreateSampleBuffer
    }
    return sampleBuffer
}

private enum AudioSampleBufferFixtureError: Error {
    case cannotCreateFormat
    case cannotCreateData
    case cannotCreateSampleBuffer
}
