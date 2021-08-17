### AVCustomEditOSX ###

====================================================================================
DESCRIPTION:

A simple AVFoundation based movie editing application demonstrating custom compositing to add transitions. The sample demonstrates the use of custom compositors to add transitions to an AVMutableComposition. It implements the AVVideoCompositing and AVVideoCompositionInstruction protocols to have access to individual source frames, which are then be rendered using OpenGL off screen rendering. 
This sample is ARC-enabled.

====================================================================================

The main files are as follows:

APLAppDelegate.m/.h:
The app delegate which handles setup, playback and export of AVMutableComposition along with other user interactions like scrubbing, toggling play/pause, selecting transition type.

APLSimpleEditor.m/.h:
 This class setups an AVComposition with relevant AVVideoCompositions using the provided clips and time ranges.

APLCustomVideoCompositionInstruction.m/.h:
 Custom video composition instruction class implementing AVVideoCompositionInstruction protocol.

APLCustomVideoCompositor.m/.h:
 Custom video compositor class implementing AVVideoCompositing protocol.

APLOpenGLRenderer.m/.h:
 Base class renderer setups an CGLContextObj for rendering, it also loads, compiles and links the vertex and fragment shaders.

APLDiagonalWipeRenderer.m/.h:
 A subclass of APLOpenGLRenderer, renders the given source buffers to perform a diagonal wipe over the transition time range.

APLCrossDissolveRenderer.m/.h:
 A subclass of APLOpenGLRenderer, renders the given source buffers to perform a cross dissolve over the transition time range.

====================================================================================
Copyright © 2013 Apple Inc. All rights reserved.