//
// Created by Bq Lin on 2021/8/30.
// Copyright © 2021 Bq. All rights reserved.
//

import Cocoa
import MetalKit

class ViewController: NSViewController {
    @IBOutlet var devicePolicyPopUp: NSPopUpButton!
    @IBOutlet var supportedDevicePopUp: NSPopUpButton!
    @IBOutlet var directDisplayDeviceLabel: NSTextField!

    var renderers: [Renderer] = []
    var supportedDevices: [MTLDevice] = []

    var currentDeviceIndex = 0
    var directDisplayDevice: MTLDevice?
    var metalDeviceObserver: NSObject!

    var frameNumber = 0
    var hotPlugDevice: MTLDevice?
    var hotPlugEvent: HotPlugEvent!
    var notificationObservers = [NSObjectProtocol]()
    var metalView: MTKView { view as! MTKView }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        devicePolicyPopUp.removeAllItems()
        let item = NSMenuItem(title: "Auto Select Best Device for Display", action: nil, keyEquivalent: "")
        devicePolicyPopUp.menu?.addItem(item)

        supportedDevicePopUp.removeAllItems()
        supportedDevicePopUp.isEnabled = false

        let availableDevices = MTLCopyAllDevicesWithObserver { [weak self] device, name in
            self?.markHotPlugNotification(device: device, name: name)
        }
        assert(!availableDevices.devices.isEmpty, "该设备不支持Metal设备")
        metalDeviceObserver = availableDevices.observer

        metalView.delegate = self
        metalView.depthStencilPixelFormat = .depth32Float_stencil8
        metalView.colorPixelFormat = .bgra8Unorm_srgb
        metalView.sampleCount = 1

        availableDevices.devices.forEach { device in
            setupDevice(device)
        }
    }

    func setupDevice(_ device: MTLDevice?) {
        guard let device = device else { return }
        let renderer = Renderer(view: metalView, device: device)
        renderers.append(renderer)
        supportedDevices.append(device)
        let item = NSMenuItem(title: device.name, action: nil, keyEquivalent: "")
        item.representedObject = device
        supportedDevicePopUp.menu?.addItem(item)

        if supportedDevices.count > 1, devicePolicyPopUp.indexOfItem(withTitle: "Manually Select Device") == -1 {
            let item = NSMenuItem(title: "Manually Select Device", action: nil, keyEquivalent: "")
            devicePolicyPopUp.menu?.addItem(item)
        }
        renderer.updateDrawableSize(metalView.drawableSize)
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        notificationObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] notification in
            self?.chooseSystemPreferredDevice()
        })
        notificationObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: nil, queue: .main) { [weak self] notification in
            self?.chooseSystemPreferredDevice()
        })
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        notificationObservers.forEach {
            NotificationCenter.default.removeObserver($0)
        }
        MTLRemoveDeviceObserver(metalDeviceObserver)
    }

    func chooseSystemPreferredDevice() {
        queryForDeviceDrvingDisplay()

        if let directDisplayDevice = directDisplayDevice {
            if (devicePolicyPopUp.indexOfSelectedItem == DeviceSelectionMode.displayOptimal.rawValue && supportedDevices[currentDeviceIndex] !== directDisplayDevice) || metalView.device == nil {
                handleDeviceSelection(directDisplayDevice)
            }
        } else {
            handleDeviceSelection(MTLCreateSystemDefaultDevice()!)
        }
    }

    func handleDeviceSelection(_ device: MTLDevice) {
        metalView.device = device
        currentDeviceIndex = supportedDevices.firstIndex { $0 === device }!

        for item in supportedDevicePopUp.menu!.items {
            if device === item.representedObject! as AnyObject {
                supportedDevicePopUp.select(item)
            }
        }

        if let directDisplayDevice = directDisplayDevice {
            directDisplayDeviceLabel.stringValue = directDisplayDevice.name
            devicePolicyPopUp.selectItem(at: DeviceSelectionMode.displayOptimal.rawValue)
            supportedDevicePopUp.isEnabled = false
        } else {
            directDisplayDeviceLabel.stringValue = "None"
        }
    }

    func markHotPlugNotification(device: MTLDevice, name: MTLDeviceNotificationName) {
        switch name {
            case .wasAdded:
                hotPlugEvent = .deviceAdded
            case .removalRequested:
                hotPlugEvent = .deviceEjected
            case .wasRemoved:
                hotPlugEvent = .devicePulled
            default: break
        }
        hotPlugDevice = device
    }

    func handlePossibleHotPlugEvent() {
        switch hotPlugEvent {
        case .deviceAdded:
            setupDevice(hotPlugDevice)
        default:
            handleMTLDeviceRemoval(hotPlugDevice)
        }
    }

    func handleMTLDeviceRemoval(_ device: MTLDevice?) {
        guard let device = device else { return }
        print("处理设备移除：\(device.name)")
        let currentDevice = supportedDevices[currentDeviceIndex]

        if supportedDevices.contains(where: { $0 === device }) {
            let usingRemovedDevice = currentDevice === device
            removeDevice(device)

            if usingRemovedDevice {
                queryForDeviceDrvingDisplay()

                if let device = directDisplayDevice {
                    handleDeviceSelection(device)
                } else {
                    handleDeviceSelection(MTLCreateSystemDefaultDevice()!)
                }
            }
        } else {
            currentDeviceIndex = supportedDevices.firstIndex { currentDevice === $0 }!
        }
    }

    func removeDevice(_ device: MTLDevice) {
        renderers.removeAll { $0.device === device }
        supportedDevices.removeAll { $0 === device }
        let menuIndex = supportedDevicePopUp.menu!.indexOfItem(withRepresentedObject: device)
        supportedDevicePopUp.item(at: menuIndex)?.representedObject = nil
        supportedDevicePopUp.menu?.removeItem(at: menuIndex)

        let itemIndex = devicePolicyPopUp.indexOfItem(withTitle: "Custom")
        if supportedDevices.count <= 1, itemIndex != -1 {
            devicePolicyPopUp.menu?.removeItem(at: itemIndex)
        }
    }

    func queryForDeviceDrvingDisplay() {
        directDisplayDevice = nil

        guard
            let viewDisplayId: CGDirectDisplayID = view.window?.screen?.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID,
            let newPreferredDevice = CGDirectDisplayCopyCurrentMetalDevice(viewDisplayId)
        else {
            print("找不到设备驱动的显示器")
            return
        }

        if directDisplayDevice !== newPreferredDevice {
            for device in supportedDevices {
                if newPreferredDevice === device {
                    directDisplayDevice = device
                }
            }
        }
    }

    @IBAction func changePreference(_ sender: AnyObject) {
        let index = devicePolicyPopUp.indexOfSelectedItem
        guard let mode = DeviceSelectionMode(rawValue: index) else { return }
        switch mode {
        case .displayOptimal:
            supportedDevicePopUp.isEnabled = false
            if supportedDevices[currentDeviceIndex] !== directDisplayDevice! {
                handleDeviceSelection(directDisplayDevice!)
            }
        case .manual:
            supportedDevicePopUp.isEnabled = true
        }
    }

    @IBAction func changeRenderer(_ sender: AnyObject) {
        let device = supportedDevicePopUp.selectedItem!.representedObject! as! MTLDevice
        handleDeviceSelection(device)
    }
}

extension ViewController: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        handlePossibleHotPlugEvent()
        for renderer in renderers {
            renderer.updateDrawableSize(size)
        }
    }

    func draw(in view: MTKView) {
        handlePossibleHotPlugEvent()
        renderers[currentDeviceIndex].draw(frameNumber: frameNumber, view: view)
        frameNumber += 1
    }
}

extension ViewController {
    enum DeviceSelectionMode: Int {
        case displayOptimal, manual
    }

    enum HotPlugEvent {
        case deviceAdded, deviceEjected, devicePulled
    }
}
