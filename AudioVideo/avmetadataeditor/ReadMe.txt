### avmetadataeditor ###===========================================================================DESCRIPTION:avmetadataeditor is a command line application demonstrating the AVFoundation metadata API.

===========================================================================USAGE:

avmetadataeditor [-w] [-a] [ <options> ] src dst
avmetadataeditor [-p] [-o] [ <options> ] src
src is a path to a local file.
dst is a path to a destination file.
Options:

  -w, --write-metadata=PLISTFILE
		  Use a PLISTFILE as metadata for the destination file
  -a, --append-metadata=PLISTFILE
		  Use a PLISTFILE as metadata to merge with the source metadata for the destination file
  -p, --print-metadata=PLISTFILE
		  Write in a PLISTFILE the metadata from the source file
  -f, --file-type=UTI
		  Use UTI as output file type
  -o, --output-metadata
		  Output the metadata from the source file
  -d, --description-metadata
		  Output the metadata description from the source file
  -q, --quicktime-metadata
		  Quicktime metadata format
  -u, --quicktime-user-metadata
		  Quicktime user metadata format
  -i, --iTunes-metadata
		  iTunes metadata format
  -h, --help
		  Print this message and exit

Example plist input:

PLIST input should contain identifiers and values as keys and values correspondingly.

<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>mdta/com.apple.quicktime.description</key>
	<string>WWDC sample code</string>
	<key>mdta/com.apple.quicktime.sample.code.key</key>
	<string>Sample code</string>
</dict>
</plist>

Example use case:

The following steps are a good place to start working with the iTunes metadata format:

1) Use avmetadataeditor to export the original iTunes metadata to a plist:

avmetadataeditor -i -p test.plist test.m4v

2) Edit the plist file as you like then use avmetadataeditor to then export to a new file saving your modified metadata

avmetadataeditor -i -f com.apple.m4v-video -w test.plist input.m4v output.m4v

Note: If the export file type is not specified, the sample defaults to quicktime which will translate the metadata to the common metadata format. "com.apple.m4v-video" in the above example is the iTunes video file type and -i specifies output in the iTunes metadata plist format.===========================================================================BUILD REQUIREMENTS:Mac OS X v10.10===========================================================================RUNTIME REQUIREMENTS:Mac OS X v10.10===========================================================================PACKAGING LIST:ReadMe.txtavmetadataeditor.mavmetadataeditor.xcodeproj===========================================================================CHANGES FROM PREVIOUS VERSIONS:Version 1.0- First version.===========================================================================Copyright (C) 2011 Apple Inc. All rights reserved.