import Flutter
import Photos
import UIKit

public class SwiftReceiveSharingIntentPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    static let kMessagesChannel = "receive_sharing_intent/messages"
    static let kEventsChannelMedia = "receive_sharing_intent/events-media"
    static let kEventsChannelLink = "receive_sharing_intent/events-text"

    private var initialMedia: [SharedMediaFile]?
    private var latestMedia: [SharedMediaFile]?

    private var initialText: String?
    private var latestText: String?

    private var eventSinkMedia: FlutterEventSink?
    private var eventSinkText: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SwiftReceiveSharingIntentPlugin()

        let channel = FlutterMethodChannel(name: kMessagesChannel, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)

        let chargingChannelMedia = FlutterEventChannel(name: kEventsChannelMedia, binaryMessenger: registrar.messenger())
        chargingChannelMedia.setStreamHandler(instance)

        let chargingChannelLink = FlutterEventChannel(name: kEventsChannelLink, binaryMessenger: registrar.messenger())
        chargingChannelLink.setStreamHandler(instance)

        registrar.addApplicationDelegate(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getInitialMedia":
            result(toJson(data: initialMedia))
        case "getInitialText":
            result(initialText)
        case "reset":
            initialMedia = nil
            latestMedia = nil
            initialText = nil
            latestText = nil
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func application(_: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any] = [:]) -> Bool {
        if let url = launchOptions[UIApplication.LaunchOptionsKey.url] as? URL {
            return handleUrl(url: url, setInitialData: true)
        } else if let activityDictionary = launchOptions[UIApplication.LaunchOptionsKey.userActivityDictionary] as? [AnyHashable: Any] { // Universal link
            for key in activityDictionary.keys {
                if let userActivity = activityDictionary[key] as? NSUserActivity {
                    if let url = userActivity.webpageURL {
                        return handleUrl(url: url, setInitialData: true)
                    }
                }
            }
        }
        return false
    }

    public func application(_: UIApplication, open url: URL, options _: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return handleUrl(url: url, setInitialData: false)
    }

    public func application(_: UIApplication, continue userActivity: NSUserActivity, restorationHandler _: @escaping ([Any]) -> Void) -> Bool {
        return handleUrl(url: userActivity.webpageURL, setInitialData: true)
    }

    private func handleUrl(url: URL?, setInitialData: Bool) -> Bool {
        debugPrint("handleUrl")

        if let url = url {
            let appDomain = Bundle.main.bundleIdentifier!
            let userDefaults = UserDefaults(suiteName: "group.\(appDomain)")
            if url.fragment == "media" {
                if let key = url.host?.components(separatedBy: "=").last,
                   let json = userDefaults?.object(forKey: key) as? Data
                {
                    let sharedArray = decode(data: json)
                    let sharedMediaFiles: [SharedMediaFile] = sharedArray.compactMap {
                        guard let path = getAbsolutePath(for: $0.path) else {
                            return nil
                        }
                        if $0.type == .video, $0.thumbnail != nil {
                            let thumbnail = getAbsolutePath(for: $0.thumbnail!)
                            return SharedMediaFile(path: path, thumbnail: thumbnail, duration: $0.duration, realname: $0.realname, type: $0.type)
                        } else if $0.type == .video, $0.thumbnail == nil {
                            return SharedMediaFile(path: path, thumbnail: nil, duration: $0.duration, realname: $0.realname, type: $0.type)
                        }

                        return SharedMediaFile(path: path, thumbnail: nil, duration: $0.duration, realname: $0.realname, type: $0.type)
                    }
                    latestMedia = sharedMediaFiles
                    if setInitialData {
                        initialMedia = latestMedia
                    }
                    eventSinkMedia?(toJson(data: latestMedia))
                }
            } else if url.fragment == "file" {
                if let key = url.host?.components(separatedBy: "=").last,
                   let json = userDefaults?.object(forKey: key) as? Data
                {
                    let sharedArray = decode(data: json)
                    let sharedMediaFiles: [SharedMediaFile] = sharedArray.compactMap {
                        guard let path = getAbsolutePath(for: $0.path) else {
                            return nil
                        }
                        return SharedMediaFile(path: path, thumbnail: nil, duration: nil, realname: $0.realname, type: $0.type)
                    }
                    latestMedia = sharedMediaFiles
                    if setInitialData {
                        initialMedia = latestMedia
                    }
                    eventSinkMedia?(toJson(data: latestMedia))
                }
            } else if url.fragment == "text" {
                if let key = url.host?.components(separatedBy: "=").last,
                   let sharedArray = userDefaults?.object(forKey: key) as? [String]
                {
                    latestText = sharedArray.joined(separator: ",")
                    if setInitialData {
                        initialText = latestText
                    }
                    eventSinkText?(latestText)
                }
            } else {
                latestText = url.absoluteString
                if setInitialData {
                    initialText = latestText
                }
                eventSinkText?(latestText)
            }
            return true
        }
        latestMedia = nil
        latestText = nil
        return false
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        if arguments as! String? == "media" {
            eventSinkMedia = events
        } else if arguments as! String? == "text" {
            eventSinkText = events
        } else {
            return FlutterError(code: "NO_SUCH_ARGUMENT", message: "No such argument\(String(describing: arguments))", details: nil)
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        if arguments as! String? == "media" {
            eventSinkMedia = nil
        } else if arguments as! String? == "text" {
            eventSinkText = nil
        } else {
            return FlutterError(code: "NO_SUCH_ARGUMENT", message: "No such argument as \(String(describing: arguments))", details: nil)
        }
        return nil
    }

    private func getAbsolutePath(for identifier: String) -> String? {
        if identifier.starts(with: "file://") || identifier.starts(with: "/var/mobile/Media") || identifier.starts(with: "/private/var/mobile") {
            return identifier.replacingOccurrences(of: "file://", with: "")
        }
        let phAsset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: .none).firstObject
        if phAsset == nil {
            return nil
        }
        let (url, _) = getFullSizeImageURLAndOrientation(for: phAsset!)
        return url
    }

    private func getFullSizeImageURLAndOrientation(for asset: PHAsset) -> (String?, Int) {
        var url: String?
        var orientation: Int = 0
        let semaphore = DispatchSemaphore(value: 0)
        let options2 = PHContentEditingInputRequestOptions()
        options2.isNetworkAccessAllowed = true
        asset.requestContentEditingInput(with: options2) { input, _ in
            orientation = Int(input?.fullSizeImageOrientation ?? 0)
            url = input?.fullSizeImageURL?.path
            semaphore.signal()
        }
        semaphore.wait()
        return (url, orientation)
    }

    private func decode(data: Data) -> [SharedMediaFile] {
        let encodedData = try? JSONDecoder().decode([SharedMediaFile].self, from: data)
        return encodedData!
    }

    private func toJson(data: [SharedMediaFile]?) -> String? {
        if data == nil {
            return nil
        }
        let encodedData = try? JSONEncoder().encode(data)
        let json = String(data: encodedData!, encoding: .utf8)!
        return json
    }

    class SharedMediaFile: Codable {
        var path: String
        var thumbnail: String? // video thumbnail
        var realname: String;
        var duration: Double? // video duration in milliseconds
        var type: SharedMediaType

        init(path: String, thumbnail: String?, duration: Double?, realname: String, type: SharedMediaType) {
            self.path = path;
            self.thumbnail = thumbnail;
            self.duration = duration;
            self.realname = realname;
            self.type = type;
        }
    }

    enum SharedMediaType: Int, Codable {
        case image
        case video
        case file
    }
}
