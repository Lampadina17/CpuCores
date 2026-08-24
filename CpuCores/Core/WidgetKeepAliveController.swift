import AVFoundation
import Foundation
import WidgetKit

enum WidgetRefreshSettings {
    static let storageKey = "widgetRefreshIntervalMilliseconds"
    static let defaultMilliseconds = 1_500
    static let minimumMilliseconds = 1_000
    static let maximumMilliseconds = 5_000
    static let stepMilliseconds = 500

    static var currentMilliseconds: Int {
        guard UserDefaults.standard.object(forKey: storageKey) != nil else {
            return defaultMilliseconds
        }
        return clamped(UserDefaults.standard.integer(forKey: storageKey))
    }

    static func clamped(_ milliseconds: Int) -> Int {
        min(max(milliseconds, minimumMilliseconds), maximumMilliseconds)
    }
}

/// Experimental sideload-only keep-alive.
///
/// An active, silent and mixable audio session keeps the containing app
/// eligible for background execution. While it is alive, the app asks
/// WidgetKit to rebuild the system widget. WidgetKit can still coalesce
/// requests because the final rendering remains owned by the system.
final class WidgetKeepAliveController: NSObject {
    static let shared = WidgetKeepAliveController()

    private let workQueue = DispatchQueue(label: "it.cpucores.widget-keep-alive")
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var silenceBuffer: AVAudioPCMBuffer?
    private var refreshTimer: DispatchSourceTimer?
    private var didConfigureEngine = false

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        workQueue.async { [weak self] in
            self?.startAudioIfNeeded()
            self?.startRefreshTimerIfNeeded()
        }
    }

    func updateRefreshInterval(milliseconds: Int) {
        let normalizedInterval = WidgetRefreshSettings.clamped(milliseconds)
        UserDefaults.standard.set(normalizedInterval, forKey: WidgetRefreshSettings.storageKey)

        workQueue.async { [weak self] in
            guard let self, self.refreshTimer != nil else { return }
            self.refreshTimer?.cancel()
            self.refreshTimer = nil
            self.startRefreshTimerIfNeeded()
        }
    }

    private func startAudioIfNeeded() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            if !didConfigureEngine {
                guard let format = AVAudioFormat(
                    standardFormatWithSampleRate: 8_000,
                    channels: 1
                ), let buffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: 8_000
                ) else {
                    return
                }

                buffer.frameLength = buffer.frameCapacity
                if let channel = buffer.floatChannelData?[0] {
                    channel.initialize(repeating: 0, count: Int(buffer.frameLength))
                }

                audioEngine.attach(playerNode)
                audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
                audioEngine.mainMixerNode.outputVolume = 0
                playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
                silenceBuffer = buffer
                didConfigureEngine = true
            }

            if !audioEngine.isRunning {
                audioEngine.prepare()
                try audioEngine.start()
            }
            if !playerNode.isPlaying {
                playerNode.play()
            }
        } catch {
            print("Widget keep-alive audio error: \(error.localizedDescription)")
        }
    }

    private func startRefreshTimerIfNeeded() {
        guard refreshTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(
            deadline: .now(),
            repeating: .milliseconds(WidgetRefreshSettings.currentMilliseconds),
            leeway: .milliseconds(250)
        )
        timer.setEventHandler {
            WidgetCenter.shared.reloadTimelines(ofKind: "widget")
        }
        timer.resume()
        refreshTimer = timer
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType),
            type == .ended
        else {
            return
        }

        workQueue.async { [weak self] in
            self?.startAudioIfNeeded()
        }
    }
}
