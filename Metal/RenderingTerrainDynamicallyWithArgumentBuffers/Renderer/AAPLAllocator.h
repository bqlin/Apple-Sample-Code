/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Declaration of the AAPLAllocator and AAPLGpuBuffer class.
 In Metal, it is required to have a ring-buffer of MTLBuffers to store per-frame-varying
 data sent to the gpu, so the CPU doesn't write to a buffer that is being read by the
 GPU.
 The AAPLAllocator and AAPLGpuBuffer objects offer an abstraction over MTLBuffers, and
 such ring-buffers. The only requirement is to call Allocator::switchToNextBufferInRing at
 the end of a frame.
*/

#import <Foundation/Foundation.h>
#import <vector>
#import <simd/simd.h>
#import <Metal/Metal.h>

class AAPLAllocator;

template <typename TElement>
class AAPLGpuBuffer
{
    friend class AAPLAllocator;
private:
    // Only allowed to be constructed by friend AAPLAllocator
    AAPLGpuBuffer (AAPLAllocator* inAllocator, size_t inOffset, size_t inSizeInBytes) :
    sourceAllocator (inAllocator),
    offsetWithinAllocator(inOffset),
    dataSizeInBytes(inSizeInBytes)
    {
        assert (inAllocator != NULL);
    }
    
public:
    AAPLGpuBuffer () :
    sourceAllocator(NULL),
    offsetWithinAllocator(0),
    dataSizeInBytes(0)
    {}

    id<MTLBuffer>  getBuffer () const;
    size_t         getOffset () const { assert (sourceAllocator != NULL); return offsetWithinAllocator; }
    void           fillInWith (const TElement* data, uint elementCount);

private:
    AAPLAllocator*     sourceAllocator;
    size_t         offsetWithinAllocator;
    size_t         dataSizeInBytes;
};

class AAPLAllocator
{
public:
    AAPLAllocator (id<MTLDevice> device, size_t size, uint8_t ringSize);
    
    void                            switchToNextBufferInRing ();
    void                            freezeNonRingBuffer ();
    template <typename TElement>
    AAPLGpuBuffer <TElement>            allocBuffer (uint inElementCount);
    bool                            isWriteable() const;
    id<MTLBuffer>                   getBuffer () { return buffers [currentBufferIdx]; }
    
private:
    // ARC automatically makes these references strong
    std::vector <id <MTLBuffer>>    buffers;
    uint8_t                         currentBufferIdx;
    size_t                          currentlyAllocated;
    bool                            isFrozen;
};

// Template inline implementations
template <typename TElement>
void AAPLGpuBuffer<TElement>::fillInWith (const TElement* data, uint elementCount)
{
    assert (sourceAllocator != NULL);
    if (!sourceAllocator->isWriteable())
    {
        assert (false);
        return;
    }
    assert (offsetWithinAllocator + sizeof (TElement) * elementCount <= getBuffer().length);
    memcpy ((uint8_t*)getBuffer().contents + offsetWithinAllocator, &(data[0]), sizeof (TElement) * elementCount);
}

template <typename TElement>
id<MTLBuffer> AAPLGpuBuffer <TElement>::getBuffer () const
{
    assert (sourceAllocator != NULL);
    return sourceAllocator->getBuffer ();
}

template <typename TElement>
AAPLGpuBuffer <TElement> AAPLAllocator::allocBuffer (uint inElementCount)
{
#if TARGET_OS_IOS
    // Statically sized 
    static const size_t alignment = 16;
#else
    static const size_t alignment = 256;
#endif
    assert (alignment >= alignof(TElement));
    
    size_t offset = (currentlyAllocated + alignment - 1) & ~(alignment - 1);
    size_t size = sizeof(TElement) * inElementCount;
    if (offset + size > buffers[0].length)
    {
        assert (false);
        NSException* oom = [NSException
                            exceptionWithName: @"OutOfMemory"
                            reason: @"Not enough space in the Metal buffer allocator to create a new Buffer."
                            userInfo: nil];
        @throw oom;
    }
    currentlyAllocated = offset + size;
    return AAPLGpuBuffer <TElement> (this, offset, size);
}
