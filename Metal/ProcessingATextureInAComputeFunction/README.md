# Processing a Texture in a Compute Function

Perform parallel calculations on structured data by placing the data in textures.


## Overview

This sample processes and displays image data using Metal textures to manage the data. The sample takes advantage of Metal's unified support for compute and graphics processing, first converting a color image to grayscale using a compute pipeline, and then rendering the resulting texture to the screen using a render pipeline. You'll learn how to read and write textures in a compute function and how to determine the work each thread performs.

You should already be familiar with compute and render functions, as well as how to create and render textures. For more information, see [Basic Tasks and Concepts](https://developer.apple.com/documentation/metal/basic_tasks_and_concepts).

## Write a Compute Function

This sample uses a compute function, also known as a *compute kernel*, to convert the texture's pixels from color to grayscale. The compute function in this sample processes the texture's pixels independently and concurrently. Its signature is shown below:

``` metal
kernel void
grayscaleKernel(texture2d<half, access::read>  inTexture  [[texture(AAPLTextureIndexInput)]],
                texture2d<half, access::write> outTexture [[texture(AAPLTextureIndexOutput)]],
                uint2                          gid        [[thread_position_in_grid]])
```

The function takes the following resource arguments:

* `inTexture`: A read-only, 2D texture that contains the input color pixels
* `outTexture`: A write-only, 2D texture that contains the output grayscale pixels

The sample specifies the `read` access qualifier for `inTexture` because it reads from the texture using the `read()` function, and the `write` access qualifier for `outTexture` because it writes to the texture using the `write()` function.

A compute function operates on a 1D, 2D, or 3D grid of threads, and part of designing any compute function is deciding the grid's dimensions and how threads in the grid correspond to input and output data. The sample operates on 2D texture data, so it uses a 2D grid with each thread processing a different pixel in the source texture.

The function's `gid` argument provides the grid coordinates for each thread. The argument's `uint2` type specifies that the grid uses 2D coordinates. The `[[thread_position_in_grid]]` attribute qualifier specifies that the GPU should generate and pass each thread's grid coordinates into the function.

A grayscale pixel has the same value for each of its RGB components. The sample calculates this value by applying weights to each component. The sample uses the Rec. 709 luma coefficients for the color-to-grayscale conversion. First, the function reads a pixel from the texture, using the thread's grid coordinates to identify which pixel each thread receives. After performing the conversion, it uses the same coordinates to write the converted pixel to the output texture.

``` metal
half4 inColor  = inTexture.read(gid);
half  gray     = dot(inColor.rgb, kRec709Luma);
outTexture.write(half4(gray, gray, gray, 1.0), gid);
```

## Execute a Compute Pass

To process the image, the sample creates an `MTLComputeCommandEncoder` object. 
``` objective-c
id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
```

To dispatch the compute command, the sample needs to determine how large a grid to create when it executes the kernel, and the sample calculates this at initialization time. As described earlier, this sample uses a grid where each thread corresponds to a pixel in the texture, so the grid must be at least as large as the 2D image. For simplicity, the sample uses a 16 x 16 threadgroup size, which is small enough to be used by any GPU. In practice, however, selecting an efficient threadgroup size depends on both the size of the data and the capabilities of a specific device object.

``` objective-c
// Set the compute kernel's threadgroup size to 16 x 16.
_threadgroupSize = MTLSizeMake(16, 16, 1);

// Calculate the number of rows and columns of threadgroups given the size of the
// input image. Ensure that the grid covers the entire image (or more).
_threadgroupCount.width  = (_inputTexture.width  + _threadgroupSize.width -  1) / _threadgroupSize.width;
_threadgroupCount.height = (_inputTexture.height + _threadgroupSize.height - 1) / _threadgroupSize.height;
// The image data is 2D, so set depth to 1.
_threadgroupCount.depth = 1;
```

The sample encodes a reference to the compute pipeline and the input and output textures, and then encodes the compute command.
``` objective-c

[computeEncoder setComputePipelineState:_computePipelineState];

[computeEncoder setTexture:_inputTexture
                   atIndex:AAPLTextureIndexInput];

[computeEncoder setTexture:_outputTexture
                   atIndex:AAPLTextureIndexOutput];

[computeEncoder dispatchThreadgroups:_threadgroupCount
               threadsPerThreadgroup:_threadgroupSize];

[computeEncoder endEncoding];
```

After finishing the compute pass, the sample encodes a render pass in the same command buffer, passing the output texture from the compute command as the input to the drawing command.

Metal automatically tracks dependencies between the compute and render passes. When the sample sends the command buffer to be executed, Metal detects that the compute pass writes to the output texture and the render pass reads from it, and makes sure the GPU finishes the compute pass before starting the render pass.
