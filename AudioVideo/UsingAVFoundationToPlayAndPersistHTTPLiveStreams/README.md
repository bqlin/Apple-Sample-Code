# Using AVFoundation to Play and Persist HTTP Live Streams

Play HTTP Live Streams and preserve streams on disk for offline play back.

## Overview

This sample provides a catalog of HTTP Live Streams (HLS) that you can play by tapping the row in the table corresponding to the stream. To manage the download of an HLS stream, tap the accessory button associated with the stream in the row in the table. Tapping the accessory button causes a transition to a new view controller which provides an interface to initiate a download, cancel an already running download, or delete a downloaded HLS stream from the device. 

The sample creates and initializes an [`AVAggregateAssetDownloadTask`](https://developer.apple.com/documentation/avfoundation/avaggregateassetdownloadtask) for the download of an HLS stream. Only the default media selections for each of the asset's media selection groups are downloaded (these are indicated in the HLS playlist `EXT-X-MEDIA` tags by a `DEFAULT` attribute of `YES`).

*NOTE*

* This sample does not support saving FairPlay Streaming (FPS) content. For a version of the sample that demonstrates how to download FPS content, see [FairPlay Streaming Server SDK](https://developer.apple.com/streaming/fps/).

## Getting Started

Build and run the sample on a device running iOS 11.0 or later.

**IMPORTANT**
* The APIs demonstrated in this sample do not work in Simulator. Run the app on a device instead.

### Adding Streams to the Sample

If you wish to add your own HLS streams to test with this sample, add an entry into the `Streams.plist` file in the Xcode project.  There are two important keys you need to provide values for:

__name__: The display name of the HLS stream in the sample.

__playlist_url__: The URL of the HLS stream's master playlist.

### Application Transport Security

If any of the streams you add are not hosted securely, you will need to add an Application Transport Security (ATS) exception in the `Info.plist` file in the Xcode project.  More information on ATS and the relevant plist keys can be found in the `NSAppTransportSecurity` section of the [Information Property List Key Reference](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Introduction/Introduction.html).

## Play an HTTP Live Stream

[`AssetListTableViewController`](x-source-tag://AssetListTableViewController) is the main user interface of this sample. It provides a list of the assets the sample can play, download, cancel download, and delete. [`AssetListManager`](x-source-tag://AssetListManager) provides a list of assets to present in the `AssetListTableViewController`.

[`AssetPlaybackManager`](x-source-tag://AssetPlaybackManager) is responsible for playing downloaded assets, and it uses key-value observing (KVO) to monitor playback-related changes to the [`AVURLAsset`](https://developer.apple.com/documentation/avfoundation/avurlasset), [`AVPlayer`](https://developer.apple.com/documentation/avfoundation/avplayer), and [`AVPlayerItem`](https://developer.apple.com/documentation/avfoundation/avplayeritem) objects it manages. A player item’s [`status`](https://developer.apple.com/documentation/avfoundation/avplayeritem/1389493-status) emits a KVO change notification when its status changes. The app monitors these changes and initiates playback when the `status` property indicates the player item is ready to play. The app observes the `AVURLAsset` [`isPlayable`](https://developer.apple.com/documentation/avfoundation/avasset/1385974-isplayable) property to determine whether an AVPlayer can play the contents of the asset in a manner that meets user expectations. The app also observes the player [`currentItem`](https://developer.apple.com/documentation/avfoundation/avplayer/1387569-currentitem) property to access the player item created for a given stream. 

The [`StreamListManager`](x-source-tag://StreamListManager) class manages loading and reading the contents of the `Streams.plist` file in the app bundle.

To play an item, tap one of the rows in the table. Tapping the item causes a transition to a new view controller. As part of that transition, the table view creates an `AssetPlaybackManager` and assigns the appropriate asset to it, as shown in the following example:

``` swift
override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    super.prepare(for: segue, sender: sender)

    if segue.identifier == AssetListTableViewController.presentPlayerViewControllerSegueID {
        guard let cell = sender as? AssetListTableViewCell,
            let playerViewControler = segue.destination as? AVPlayerViewController else { return }

        /*
         Grab a reference for the destinationViewController to use in later delegate callbacks from
         AssetPlaybackManager.
         */
        playerViewController = playerViewControler

        // Load the new Asset to playback into AssetPlaybackManager.
        AssetPlaybackManager.sharedManager.setAssetForPlayback(cell.asset)
    }
}
```
[View in Source](x-source-tag://PreparePlayStream)

Assigning an asset to the `AssetPlaybackManager` causes it to create an `AVPlayerItem` for the asset, removing any previous asset in the process:

``` swift
private var asset: Asset? {
    willSet {
        /// Remove any previous KVO observer.
        guard let urlAssetObserver = urlAssetObserver else { return }
        
        urlAssetObserver.invalidate()
    }
    
    didSet {
        if let asset = asset {
            urlAssetObserver = asset.urlAsset.observe(\AVURLAsset.isPlayable, options: [.new, .initial]) { [weak self] (urlAsset, _) in
                guard let strongSelf = self, urlAsset.isPlayable == true else { return }
                
                strongSelf.playerItem = AVPlayerItem(asset: urlAsset)
                strongSelf.player.replaceCurrentItem(with: strongSelf.playerItem)
            }
        } else {
            playerItem = nil
            player.replaceCurrentItem(with: nil)
            readyForPlayback = false
        }
    }
}
```
[View in Source](x-source-tag://PlayStreamCreatePlayerItem)

The `AssetPlaybackManager` uses KVO to monitor the `AVPlayerItem` object's `status`, and initiates playback when the `status` becomes ready to play: 

``` swift
playerItemObserver = playerItem?.observe(\AVPlayerItem.status, options: [.new, .initial]) { [weak self] (item, _) in
    guard let strongSelf = self else { return }
    
    if item.status == .readyToPlay {
        if !strongSelf.readyForPlayback {
            strongSelf.readyForPlayback = true
            strongSelf.delegate?.streamPlaybackManager(strongSelf, playerReadyToPlay: strongSelf.player)
        }
    } else if item.status == .failed {
        let error = item.error
        
        print("Error: \(String(describing: error?.localizedDescription))")
    }
```
[View in Source](x-source-tag://PlayerItemReadyToPlay)

## Download an HTTP Live Stream

[`AssetPersistenceManager`](x-source-tag://AssetPersistenceManager) is the main class in this sample that demonstrates how to manage downloading HLS streams. It includes methods for starting and canceling downloads, deleting existing assets from the user's device, and monitoring the download.

When the user initiates a download by tapping the accessory button in the corresponding stream's table view cell, an instance of `AssetPersistenceManager` calls the following function to create an `AVAggregateAssetDownloadTask` object to download multiple [`AVMediaSelection`](https://developer.apple.com/documentation/avfoundation/avmediaselection) for the [`AVURLAsset`](https://developer.apple.com/documentation/avfoundation/avurlasset) of the HLS stream:

``` swift
func downloadStream(for asset: Asset) {

    // Get the default media selections for the asset's media selection groups.
    let preferredMediaSelection = asset.urlAsset.preferredMediaSelection

    /*
     Creates and initializes an AVAggregateAssetDownloadTask to download multiple AVMediaSelections
     on an AVURLAsset.
     
     For the initial download, we ask the URLSession for an AVAssetDownloadTask with a minimum bitrate
     corresponding with one of the lower bitrate variants in the asset.
     */
    guard let task =
        assetDownloadURLSession.aggregateAssetDownloadTask(with: asset.urlAsset,
                                                           mediaSelections: [preferredMediaSelection],
                                                           assetTitle: asset.stream.name,
                                                           assetArtworkData: nil,
                                                           options:
            [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 265_000]) else { return }

    // To better track the AVAssetDownloadTask, set the taskDescription to something unique for the sample.
    task.taskDescription = asset.stream.name

    activeDownloadsMap[task] = asset

    task.resume()

    var userInfo = [String: Any]()
    userInfo[Asset.Keys.name] = asset.stream.name
    userInfo[Asset.Keys.downloadState] = Asset.DownloadState.downloading.rawValue
    userInfo[Asset.Keys.downloadSelectionDisplayName] = displayNamesForSelectedMediaOptions(preferredMediaSelection)

    NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil, userInfo: userInfo)
}
```
[View in Source](x-source-tag://DownloadStream)

**NOTE**

* You cannot save a live HLS stream while it is in progress. If you try to save a live HLS stream, the system throws an exception. Only Video On Demand (VOD) streams support offline playback.

## Cancel an HTTP Live Stream

Tap the accessory button in the corresponding stream's table view cell to reveal the accessory view, then tap Cancel to stop downloading the stream. The following function in `AssetPersistenceManager` cancels the download by calling the `URLSessionTask` [`cancel`](https://developer.apple.com/documentation/foundation/urlsessiontask/1411591-cancel) method.

``` swift
func cancelDownload(for asset: Asset) {
    var task: AVAggregateAssetDownloadTask?

    for (taskKey, assetVal) in activeDownloadsMap where asset == assetVal {
        task = taskKey
        break
    }

    task?.cancel()
}
```
[View in Source](x-source-tag://CancelDownload)

## Remove an HTTP Live Stream from Disk

Tap the accessory button in the corresponding stream's table view cell to reveal the accessory view, then tap Delete to delete the downloaded stream file. The following function in `AssetPersistenceManager` removes a downloaded stream on the device. First the asset URL corresponding to the file on the device is identified, then the `FileManager` [`removeItem`](https://developer.apple.com/documentation/foundation/filemanager/1413590-removeitem) method is called to remove the downloaded stream at the specified URL.

``` swift
func deleteAsset(_ asset: Asset) {
    let userDefaults = UserDefaults.standard

    do {
        if let localFileLocation = localAssetForStream(withName: asset.stream.name)?.urlAsset.url {
            try FileManager.default.removeItem(at: localFileLocation)

            userDefaults.removeObject(forKey: asset.stream.name)

            var userInfo = [String: Any]()
            userInfo[Asset.Keys.name] = asset.stream.name
            userInfo[Asset.Keys.downloadState] = Asset.DownloadState.notDownloaded.rawValue

            NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil,
                                            userInfo: userInfo)
        }
    } catch {
        print("An error occured deleting the file: \(error)")
    }
}
```
[View in Source](x-source-tag://RemoveDownload)

## Measure Playback Performance

[`PerfMeasurements`](x-source-tag://PerfMeasurements) contains utility code to measure key performance indicators (KPI) during streaming playback. This code makes use of the [`AVPlayerItemAccessLog`](https://developer.apple.com/documentation/avfoundation/avplayeritemaccesslog) for many of its calculations. An `AVPlayerItemAccessLog` object accumulates key metrics about network playback and presents them as a collection of [`AVPlayerItemAccessLogEvent`](https://developer.apple.com/documentation/avfoundation/avplayeritemaccesslogevent) instances. Each event instance collates the data that relates to each uninterrupted period of playback.

**NOTE**

* You can view the various performance indicators in the console during playback.

For example, here's the code to calculate the total time spent playing the stream, obtained from the `AVPlayerItemAccessLog`:

``` swift
var totalDurationWatched: Double {
    // Compute total duration watched by iterating through the AccessLog events.
    var totalDurationWatched = 0.0
    if accessLog != nil && !accessLog!.events.isEmpty {
        for event in accessLog!.events where event.durationWatched > 0 {
                totalDurationWatched += event.durationWatched
        }
    }
    return totalDurationWatched
}
```
[View in Source](x-source-tag://TotalDurationWatched)
