/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the AAPLAllocator object.
*/

#import "AAPLAllocator.h"

AAPLAllocator::AAPLAllocator (id<MTLDevice> device, size_t size, uint8_t ringSize) :
currentBufferIdx (0),
currentlyAllocated (0),
isFrozen (false)
{
    assert (ringSize > 0);
    for (uint8_t i = 0; i < ringSize; i++)
    {
        buffers.push_back ([device newBufferWithLength:size options:MTLResourceOptionCPUCacheModeDefault]);
    }
}
    
void AAPLAllocator::switchToNextBufferInRing ()
{
    assert (buffers.size() > 1);
    
    // A ring buffer should never be frozen
    assert (! isFrozen);
    currentBufferIdx = (currentBufferIdx+1) % buffers.size();
}

void AAPLAllocator::freezeNonRingBuffer ()
{
    if (buffers.size() > 1)
    {
        assert (false);
        return;
    }
    assert (currentlyAllocated > 0);
    isFrozen = true;
}

bool AAPLAllocator::isWriteable () const
{
    return !isFrozen;
}
    
