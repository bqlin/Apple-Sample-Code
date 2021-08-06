# Creating a Movie Player App with Basic Playback Controls

Play movies using a custom interface that implements simple playback functionality.

## Overview

This sample shows how to create a simple movie playback app using the [AVFoundation][1] framework (not [`AVKit`](https://developer.apple.com/documentation/avkit)). The [AVFoundation][1] objects that manage a player's visual output don't present any playback controls. Use the sample to build your own playback controls that implement the functionality to play, pause, fast forward, rewind, and scrub through movies.

[1]:https://developer.apple.com/documentation/avfoundation

## Play a Movie in Fast Forward or Reverse

You set the player’s [`rate`][54] property to change the rate of playback. A value of 1.0 plays the movie at its natural rate. Setting the `rate` to 0.0 is the same as pausing playback using the [`pause`](https://developer.apple.com/documentation/avfoundation/avplayer/1387895-pause) method. Set the [`rate`][54] property to a number greater than 1.0 to fast forward, and to a number less than 0.0 to reverse.

In this sample, the `playFastForward` method adds as much as 2.0 to the current player [`rate`][54] property, up to a maximum `rate` value of 2.0, when the user taps the Fast Forward button in the UI.

``` swift
// Play fast forward no faster than 2.0.
player.rate = min(player.rate + 2.0, 2.0)
```
[View in Source](x-source-tag://FastForwardPlayback)

The `playReverse` method subtracts as much as 2.0 from the current player [`rate`][54] property, down to a minimum `rate` value of –2.0, when the user taps the Play Reverse button in the UI.

``` swift
// Reverse no faster than -2.0.
player.rate = max(player.rate - 2.0, -2.0)
```
[View in Source](x-source-tag://SetReversePlayback)

You determine whether the player item supports fast forward playback by using the [`canPlayFastForward`](https://developer.apple.com/documentation/avfoundation/avplayeritem/1389096-canplayfastforward) property. Similarly, you determine the type of reverse play supported by using:

* [`canPlayReverse`](https://developer.apple.com/documentation/avfoundation/avplayeritem/1385591-canplayreverse) — Supports a rate value of –1.0
*  [`canPlaySlowReverse`](https://developer.apple.com/documentation/avfoundation/avplayeritem/1390598-canplayslowreverse) — Supports rate values from 0.0 to –1.0
*  [`canPlayFastReverse`](https://developer.apple.com/documentation/avfoundation/avplayeritem/1390493-canplayfastreverse) — Supports rate values less than –1.0

The `setupPlayerObservers` method in this sample defines key-value observers on the player and player item properties. These observers enable or disable the fast forward and reverse buttons in the UI based on the reported values of the observed properties.

## Play a Movie at its Natural Rate

The `togglePlay` method toggles the playback state of the movie when the user taps the Play button in the UI. It first uses the [`timeControlStatus`](https://developer.apple.com/documentation/avfoundation/avplayer/1643485-timecontrolstatus) property to determine whether playback is in progress or paused. If the player is paused, the `togglePlay` method initiates playback of the movie at its natural rate (1.0) by invoking the [`play`](https://developer.apple.com/documentation/avfoundation/avplayer/1386726-play) method. If the player is already playing, the `togglePlay` method pauses playback by invoking the [`pause`](https://developer.apple.com/documentation/avfoundation/avplayer/1387895-pause) method.

## Perform Movie Scrubbing

To handle movie scrubbing, this sample defines the `timeSliderDidChange` action method on a slider control in the UI. Adjusting the slider control calls this method, which then sets the player time to the new value using the [`AVPlayer`][50]  [`seek(to:)`](https://developer.apple.com/documentation/avfoundation/avplayer/1385953-seek) method. The video corresponding to the new time is then rendered in the view.

``` swift
@IBAction func timeSliderDidChange(_ sender: UISlider) {
    let newTime = CMTime(seconds: Double(sender.value), preferredTimescale: 600)
    player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
}
```
[View in Source](x-source-tag://TimeSliderDidChange)

This sample also adds a periodic time observer to the player. The observer requests the periodic invocation of a given block during playback to report the current time of the player. The observer invokes the block periodically at the interval specified, interpreted according to the timeline of the current player item. The observer also invokes the block whenever time jumps — for example, during movie scrubbing — and whenever playback starts or stops. 

The code in the observer updates the movie's current time value, displayed by the time slider control in the UI, and keeps it in sync with the movie playback.

``` swift
timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval,
                                                   queue: .main) { [unowned self] time in
    let timeElapsed = Float(time.seconds)
    self.timeSlider.value = timeElapsed
    self.startTimeLabel.text = self.createTimeString(time: timeElapsed)
}
```
[View in Source](x-source-tag://PeriodicTimeObserver)

[50]:https://developer.apple.com/documentation/avfoundation/avplayer
[51]:https://developer.apple.com/documentation/avfoundation/avplayeritem
[54]:https://developer.apple.com/documentation/avfoundation/avplayer/1388846-rate


