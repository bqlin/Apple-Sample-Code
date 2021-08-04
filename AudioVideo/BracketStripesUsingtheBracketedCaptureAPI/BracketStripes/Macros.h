/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Helpful macros.
 */

// Clamp _value to range [_lo, _hi]
#define CLAMP(_value, _lo, _hi) \
    MAX( (_lo), MIN( (_hi), (_value) ) )
