//  Converted to Swift 4 by Swiftify v4.1.6613 - https://objectivec2swift.com/
//
//  PVSettingsModel.swift
//  Provenance
//
//  Created by James Addyman on 21/08/2013.
//  Copyright (c) 2013 James Addyman. All rights reserved.
//

import Foundation

internal func minutes(_ minutes : Double) -> TimeInterval {
    return TimeInterval(60 * minutes)
}

public protocol UserDefaultsRepresentable {
    var defaultsValue : Any {get}
}

extension UserDefaultsRepresentable where Self:RawRepresentable {
    public var defaultsValue : Any {
        return self.rawValue
    }
}

public protocol SettingModel : NSObjectProtocol, UserDefaultsRepresentable {
    associatedtype T : Any
    var title : String {get}
    var info : String? {get}
    var defaultValue : T {get}
    var value : T {get set}
}

//extension SettingModel {
//    init(_ defaultValue : Bool, title: String, info: String? = nil) {
//        self.defaultValue = defaultValue
//        self.value = defaultValue
//        self.title = title
//        self.info = info
//        super.init()
//    }
//}

@objcMembers
@objc public final class BoolSetting : NSObject, SettingModel {
    public var defaultsValue: Any {
        return value
    }

    public let defaultValue : Bool
    public var value : Bool
    public var title : String
    public let info : String?

    required public init(_ defaultValue : Bool, title: String, info: String? = nil) {
        self.defaultValue = defaultValue
        self.value = defaultValue
        self.title = title
        self.info = info
        super.init()
    }
}

/// Root class that sets/loads settings by Swift's introspection 'Mirrored'
/// Features
/// 0 Full compatible with ObjC and Swift
/// 1 Looks to see if value exists in UserDefaults, if yes, uses that, if no, uses the default let value
/// 2 Automatically uses kvo to detected changes and stores in user defaults.
/// 3 Supports custom types with `UserDefaultsRepresentable` protocol. RawRepresentable has default implimentation
/// 4 Load default settings from Defaults.plist (Optional)
/// 5 Quick flip of Bools via keyPath. .toggle(\.keyPath)
/// 6 Supports grouping settings into sub-keys by using local NSObject classes

public class MirroredSettings : NSObject {

    var plistPath : String? {
        return  Bundle.main.path( forResource: "Defaults", ofType: "plist" )
    }

    override init() {
        super.init()

        if let path = plistPath {
            UserDefaults.standard.register( defaults: NSDictionary( contentsOfFile: path ) as? [ String : Any ] ?? [ : ] )
        }

        setInitialValues(self, rootKey: nil)
        UserDefaults.standard.synchronize()
    }

    final private func setInitialValues(_ settings : NSObject, rootKey: String? = nil) {
        for c in Mirror(reflecting: settings).children {
            guard let key = c.label else {
                continue
            }

            let keyPath : String
            if let rootKey = rootKey {
                keyPath = [rootKey, key].joined(separator: ".")
            } else {
                keyPath = key
            }

            if let currentValue = UserDefaults.standard.object(forKey: keyPath) ?? UserDefaults.standard.object(forKey: "k\(key.uppercased())Key") {
                // Handle case where value was previously set
                self.setValue(currentValue, forKeyPath: keyPath)
            } else {
                if let e = c.value as? UserDefaultsRepresentable {
                    UserDefaults.standard.set(e.defaultsValue, forKey: keyPath)
                } else if let sub = c.value as? NSObject {
                    setInitialValues(sub, rootKey: key)
                } else {
                    UserDefaults.standard.set(c.value, forKey: keyPath)
                }
            }

            // TODO: rx observers?
            self.addObserver(self, forKeyPath: keyPath, options:[.new], context:nil)
        }
    }

    deinit {
        for c in Mirror( reflecting: self ).children {
            guard let key = c.label else {
                continue
            }
            // TODO: This doesn't handle sub paths
            self.removeObserver( self, forKeyPath: key)
        }
    }

    @discardableResult
    final func toggle<T:MirroredSettings>(_ key : ReferenceWritableKeyPath<T, Bool>) -> Bool {
        let newValue = !(self as! T)[keyPath: key]
        (self as! T)[keyPath: key] = newValue
        return newValue
    }
}

extension MirroredSettings {
    final private func searchAndSet(_ keyPath: String, on: Any, to newValue: Any, rootKey: String? = nil) -> Bool {
        for c in Mirror( reflecting: on ).children {
            guard let key = c.label else { continue }

            // Handle sub-key paths
            var split = keyPath.components(separatedBy: ".")
            if split.count > 1 {
                var lrootKey = String(split.first!)
                if let rootKey = rootKey {
                    lrootKey = rootKey + "." + lrootKey
                }
                split.removeFirst()
                let subKeyPath = split.joined(separator: ".")
                let found = searchAndSet(subKeyPath, on: c.value, to: newValue, rootKey: lrootKey)
                if found {
                    return true
                }
            } else if key == keyPath {
                let myKeyPath : String
                if let rootKey = rootKey {
                    myKeyPath = rootKey + "." + keyPath
                } else {
                    myKeyPath = keyPath
                }

                if let e = newValue as? UserDefaultsRepresentable {
                    UserDefaults.standard.set(e.defaultsValue, forKey: myKeyPath)
                } else {
                    UserDefaults.standard.set(newValue, forKey: myKeyPath)
                }

                return true
            }
        }

        return false
    }

    public override func observeValue( forKeyPath keyPath: String?, of object: Any?, change: [ NSKeyValueChangeKey : Any ]?, context: UnsafeMutableRawPointer? ) {

        guard let myChange = change, let newValue = myChange[.newKey], let keyPathNotNil = keyPath else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }

        let found = searchAndSet(keyPathNotNil, on: self, to: newValue, rootKey: nil)

        if !found {
            super.observeValue(forKeyPath: keyPathNotNil, of: object, change: change, context: context)
        } else {
            UserDefaults.standard.synchronize()
        }
    }
}

@objcMembers
@objc public final class PVSettingsModel: MirroredSettings {
    @objc public static let shared = PVSettingsModel()

    @objc public class DebugOptions : NSObject {
        @objc public dynamic var iCloudSync = false
//        @objc public dynamic var unsupportedCores = false
//        @objc public dynamic var multiThreadedGL = BoolSetting(false, title: "Multi-threaded GL", info: "Use threaded GLES calls.")
        @objc public dynamic var multiThreadedGL = false
    }

    @objc public dynamic var debugOptions = DebugOptions()

    @objc public dynamic var autoSave = true
    @objc public dynamic var timedAutoSaves = true
    @objc public dynamic var timedAutoSaveInterval = minutes(10)

    @objc public dynamic var askToAutoLoad = true
    @objc public dynamic var autoLoadSaves = false

    @objc public dynamic var disableAutoLock = false
    @objc public dynamic var buttonVibration = true

    @objc public dynamic var imageSmoothing = false
    @objc public dynamic var crtFilterEnabled = false
    @objc public dynamic var nativeScaleEnabled = true

    @objc public dynamic var showRecentSaveStates = true
    @objc public dynamic var showGameBadges = true
    @objc public dynamic var showRecentGames = true

    @objc public dynamic var showFPSCount = false

    @objc public dynamic var showGameTitles = true
    @objc public dynamic var gameLibraryScale = 1.0

    @objc public dynamic var webDavAlwaysOn = false
    @objc public dynamic var myiCadeControllerSetting = iCadeControllerSetting.disabled

    @objc public dynamic var controllerOpacity :CGFloat = 0.8
    @objc public dynamic var buttonTints = true

    #if os(tvOS)
    @objc public dynamic var startSelectAlwaysOn = true
    #else
    @objc public dynamic var startSelectAlwaysOn = false
    #endif

    @objc public dynamic var allRightShoulders = false

    @objc public dynamic var volume : Float = 1.0
    @objc public dynamic var volumeHUD = true
}
