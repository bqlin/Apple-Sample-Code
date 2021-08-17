
AVMediaSelectionDemo
====================

This sample demonstrates how to select different media selection options like closed captions, subtitles and audio language options on different player items. This sample sets up four views each handling their own AVPlayer and AVPlayerItems. A user can select an option through the contextual pop up menu, which in turn gets set on the corresponding AVPlayerItem.


Main Classes

APLDocument
The players document class. It sets up four AVPlaybackViews each of which handle their own AVPlayers. It manages adjusting the playback rate, enables and disables UI elements as appropriate, sets up a time observer for updating the current time (which the UI’s time slider is bound to). The document window is defined in APLDocument.xib.

APLPlaybackView
The player view class. It sets up AVPlayer and AVPlayerLayer. It defines a protocol for its delegate to receive all user interactions such as keyboard hits and mouse down events.

APLDocumentController
Document controller subclass to handle opening URLs. The window used to enter a URL is defined in OpenURL.xib.

StooopidSubtitlesDemo.mov
A sample movie provided along with the sample code, which has multiple audible and legible options.

===========================================================================
Copyright (C) 2013 Apple Inc. All rights reserved.
