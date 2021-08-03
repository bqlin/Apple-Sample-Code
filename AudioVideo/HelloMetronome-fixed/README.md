# Hello Metronome

Simple demonstration of a metronome using AVAudioEngine and AVAudioPlayerNode to schedule buffers for timing accurate playback using scheduleBuffer:atTime:options:completionHandler:. The implementation also provides for a delegate object to call with the method (metronomeTicking:bar:beat:) which can be used for timing or to provide UI.

The macOS version is a command line app and can use an included .caf file for the metronome bip sound or bips will be generated via a TriangleWaveGenerator class. Use the -f option to use the .caf file.

The iOS version provides a simple UI implementing the delegate method (metronomeTicking:bar:beat:) and uses the TriangleWaveGenerator class to generate the metronome bip sounds.

The watchOS version provides a slightly more complex UI with a delegate method to draw the animation for each tick and also uses the TriangleWaveGenerator class to generate the metronome bip sounds.

## Main Files

Metronome.m
- Source file for mentronome implementation in macOS and watchOS targets.

Metronome.h
- Header file for metronome class implemented in Metronome.m

Metronome.swift
- Source file for metronome implementation in iOS target.

TWGenerator.swift
- Generic TriangleWaveGenerator swift class used by all targets.

## Version History

1.0 Initial release.

1.1 Swift implementation, interoperability and general cleanup.
    * added swift triangle wave generator used by all targets
    * added swift Metronome class implementation for iOS target
    * cleaned up and reorganized project 

## Requirements

### Build

Xcode 8.2.1 or later, macOS 10.12, iOS 10.2, watchOS 3.1 SDKs

### Runtime

macOS 10.9 or greater
iOS 9.3 or greater
watchOS 3.0 or greater

Copyright (C) 2017 Apple Inc. All rights reserved.
