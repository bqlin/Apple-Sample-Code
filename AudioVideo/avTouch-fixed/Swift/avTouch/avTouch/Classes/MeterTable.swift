//
// Created by Bq Lin on 2021/8/10.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation

// MeterTable constructor arguments:
// inNumUISteps - the number of steps in the UI element that will be drawn.
// This could be a height in pixels or number of bars in an LED style display.
// inTableSize - The size of the table. The table needs to be large enough that there are no large gaps in the response.
// inMinDecibels - the decibel value of the minimum displayed amplitude.
// inRoot - this controls the curvature of the response. 2.0 is square root, 3.0 is cube root. But inRoot doesn't have to be integer valued, it could be 1.8 or 2.5, etc.
public class MeterTable {
    private var mMinDecibels: Double = 0
    private var mDecibelResolution: Double = 0
    private var mScaleFactor: Double = 0
    private var mTable: [Double] = []

    init(inMinDecibels: Double = -80, inTableSize: Int = 400, inRoot: Double = 2) {
        mMinDecibels = inMinDecibels
        mDecibelResolution = mMinDecibels / Double(inTableSize - 1)
        mScaleFactor = 1 / mDecibelResolution

        guard inMinDecibels < 0 else {
            fatalError("MeterTable inMinDecibels must be negative")
        }

        let minAmp = dbToAmp(db: inMinDecibels)
        let ampRange = 1 - minAmp
        let invAmpRange = 1 / ampRange

        let rroot = 1 / inRoot
        for i in 0 ..< inTableSize {
            let decibels = Double(i) * mDecibelResolution
            let amp = dbToAmp(db: decibels)
            let adjAmp = (amp - minAmp) * invAmpRange
            mTable.append(pow(adjAmp, rroot))
        }
    }
}

public extension MeterTable {
    func value(at inDecibels: Double) -> Double {
        guard inDecibels >= mMinDecibels else { return 0 }
        guard inDecibels < 0 else { return 1 }
        let index = Int(inDecibels * mScaleFactor)
        return mTable[index]
    }
}

private extension MeterTable {
    func dbToAmp(db: Double) -> Double {
        pow(10, 0.05 * db)
    }
}
