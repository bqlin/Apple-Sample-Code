# Using Metal to Draw a View's Contents

Create a MetalKit view and a render pass to draw the view's contents.

## Overview

In this sample, you'll learn the basics of rendering graphics content with Metal. 
You'll use the MetalKit framework to create a view that uses Metal to draw the contents of the view.  Then, you'll encode commands for a render pass that erases the view to a background color.

- Note: MetalKit automates windowing system tasks, loads textures, and handles 3D model data. See [MetalKit][MetalKit] for more information.

## Prepare a MetalKit View to Draw

MetalKit provides a class called [`MTKView`][MTKView], which is a subclass of [`NSView`][NSView] (in macOS) or [`UIView`][UIView] (in iOS and tvOS).
`MTKView` handles many of the details related to getting the content you draw with Metal onto the screen. 

An `MTKView` needs a reference to a Metal device object in order to create resources internally, so your first step is to set the view's  [`device`](https://developer.apple.com/documentation/metalkit/mtkview/1536011-device) property to an existing [`MTLDevice`][MTLDevice].

``` objective-c
_view.device = MTLCreateSystemDefaultDevice();
```

Other properties on `MTKView` allow you to control its behavior. To erase the contents of the view to a solid background color, you set its [`clearColor`](https://developer.apple.com/documentation/metalkit/mtkview/1536036-clearcolor) property. You create the color using the [`MTLClearColorMake`](https://developer.apple.com/documentation/metal/1437971-mtlclearcolormake) function, specifying the red, green, blue, and alpha values.

``` objective-c
_view.clearColor = MTLClearColorMake(0.0, 0.5, 1.0, 1.0);
```

Because you won't be drawing animated content in this sample, configure the view so that it only draws when the contents need to be updated, such as when the view changes shape:

``` objective-c
_view.enableSetNeedsDisplay = YES;
```


## Delegate Drawing Responsibilities

`MTKView` relies on your app to issue commands to Metal to produce visual content.
`MTKView` uses the delegate pattern to inform your app when it should draw.
To receive delegate callbacks, set the view's `delegate` property to an object that conforms to the [`MTKViewDelegate`][MTKViewDelegate] protocol.

``` objective-c
_view.delegate = _renderer;
```

The delegate implements two methods:

- The view calls the [`mtkView:drawableSizeWillChange:`](https://developer.apple.com/documentation/metalkit/mtkviewdelegate/1536015-mtkview) method whenever the size of the contents changes.
This happens when the window containing the view is resized, or when the device orientation changes (on iOS).
This allows your app to adapt the resolution at which it renders to the size of the view.

- The view calls the [`drawInMTKView:`](https://developer.apple.com/documentation/metalkit/mtkviewdelegate/1535942-drawinmtkview) method whenever it's time to update the view's contents.
In this method, you create a command buffer, encode commands that tell the GPU what to draw and when to display it onscreen, and enqueue that command buffer to be executed by the GPU. This is sometimes referred to as drawing a frame. You can think of a frame as all of the work that goes into producing a single image that gets displayed on the screen. In an interactive app, like a game, you might draw many frames per second.

In this sample, a class called `AAPLRenderer` implements the delegate methods and takes on the responsibility of drawing.
The view controller creates an instance of this class and sets it as the view's delegate.

## Create a Render Pass Descriptor

When you draw, the GPU stores the results into *textures*, which are blocks of memory that contain image data and are accessible to the GPU. In this sample, the `MTKView` creates all of the textures you need to draw into the view. It creates multiple textures so that it can display the contents of one texture while you render into another.

To draw, you create a *render pass*, which is a sequence of rendering commands that draw into a set of textures. When used in a render pass, textures are also called *render targets*. To create a render pass, you need a render pass descriptor, an instance of [`MTLRenderPassDescriptor`][MTLRenderPassDescriptor]. In this sample, rather than configuring your own render pass descriptor, ask the MetalKit view to create one for you.

``` objective-c
MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
if (renderPassDescriptor == nil)
{
    return;
}
```

A render pass descriptor describes the set of render targets, and how they should be processed at the start and end of the render pass. Render passes also define some other aspects of rendering that are not part of this sample. The view returns a render pass descriptor with a single color attachment that points to one of the view's textures, and otherwise configures the render pass based on the view's properties. By default, this means that at the start of the render pass, the render target is erased to a solid color that matches the view's `clearColor` property, and at the end of the render pass, all changes are stored back to the texture.

Because a view's render pass descriptor might be `nil`, you should test to make sure the render pass descriptor object is non-`nil` before creating the render pass.


## Create a Render Pass

You create the render pass by encoding it into the command buffer using a  [`MTLRenderCommandEncoder`][MTLRenderCommandEncoder] object. Call the command buffer's [`renderCommandEncoderWithDescriptor:`](https://developer.apple.com/documentation/metal/mtlcommandbuffer/1442999-rendercommandencoderwithdescript) method and pass in the render pass descriptor.

``` objective-c
id<MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
```

In this sample, you don't encode any drawing commands, so the only thing the render pass does is erase the texture. Call the encoder's `endEncoding` method to indicate that the pass is complete.

``` objective-c
[commandEncoder endEncoding];
```

## Present a Drawable to the Screen

Drawing to a texture doesn't automatically display the new contents onscreen. In fact, only some textures can be presented onscreen. In Metal, textures that can be displayed onscreen are managed by *drawable objects*, and to display the content, you present the drawable.

`MTKView` automatically creates drawable objects to manage its textures. Read the [`currentDrawable`](https://developer.apple.com/documentation/metalkit/mtkview/1535971-currentdrawable) property to get the drawable that owns the texture that is the render pass's target. The view returns a [`CAMetalDrawable`][CAMetalDrawable] object, an object connected to Core Animation.

``` objective-c
id<MTLDrawable> drawable = view.currentDrawable;
```

Call the [`presentDrawable:`](https://developer.apple.com/documentation/metal/mtlcommandbuffer/1443029-presentdrawable) method on the command buffer, passing in the drawable.

``` objective-c
[commandBuffer presentDrawable:drawable];
```

This method tells Metal that when the command buffer is scheduled for execution, Metal should coordinate with Core Animation to display the texture after rendering completes. When Core Animation presents the texture, it becomes the view's new contents. In this sample, this means that the erased texture becomes the new background for the view. The change happens alongside any other visual updates that Core Animation makes for onscreen user interface elements. 


## Commit the Command Buffer

Now that you've issued all the commands for the frame, commit the command buffer.

``` objective-c
[commandBuffer commit];
```


[MTLDevice]: https://developer.apple.com/documentation/metal/mtldevice
[MTLRenderPassDescriptor]: https://developer.apple.com/documentation/metal/mtlrenderpassdescriptor
[MTLRenderCommandEncoder]: https://developer.apple.com/documentation/metal/mtlrendercommandencoder
[MetalKit]: https://developer.apple.com/documentation/metalkit
[MTKView]: https://developer.apple.com/documentation/metalkit/mtkview
[MTKViewDelegate]: https://developer.apple.com/documentation/metalkit/mtkviewdelegate
[HelloTriangle]: https://developer.apple.com/documentation/metal
[MetalComputeBasic]: https://developer.apple.com/documentation/metal
[NSView]: https://developer.apple.com/documentation/appkit/nsview
[UIView]: https://developer.apple.com/documentation/uikit/uiview
[CAMetalDrawable]: https://developer.apple.com/documentation/quartzcore/cametaldrawable