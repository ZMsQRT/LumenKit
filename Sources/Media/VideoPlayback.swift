//
//  VideoPlayback.swift
//  对应 Flutter 侧 `video_player` 的最小封装（`MatchVideo`、`FirstRechargeVideo`
//  等弹窗里的静音自动播放）。
//
//  Flutter 用 `VideoPlayerController.networkUrl(...)` + `VideoPlayer(controller)`；
//  Swift 端只需要「静音循环播放 + 播完通知 + 首帧尺寸」，因此这里收敛成：
//
//  * `VideoPlaybackController` —— 状态（播放中 / 播完 / 视频尺寸）；
//  * `VideoSurface` —— `AVPlayerLayer` 的 SwiftUI 包装。
//

import AVFoundation
import CoreImage
import SwiftUI

// MARK: - 播放控制器

/// 保存播放意图的版本号，供播放完成通知捕获和比较。
///
/// 通知回调与主线程上的播放操作可能交错，锁保护版本号的跨线程读写。
/// 每次 play、pause、重置或销毁都会更新版本，使旧通知和旧 seek 回调失效。
private final class VideoPlaybackIntent: @unchecked Sendable {
    private let lock = NSLock()
    private var value = UUID()
    func current() -> UUID { lock.lock(); defer { lock.unlock() }; return value }
    func advance() { lock.lock(); defer { lock.unlock() }; value = UUID() }
}

/// 管理单个 AVPlayer 的资源准备、播放状态、完成通知和生命周期。
/// 状态和播放器操作均在主线程进行；异步准备及通知回调必须校验当前资源和版本。
@MainActor
open class VideoPlaybackController: ObservableObject {
    public let player: AVPlayer

    /// 播放器实际进入 playing 状态；缓冲或等待数据时为 false。
    @Published public private(set) var isPlaying = false
    /// 非循环资源播放结束后为 true；replay 或 reset 会清除。
    @Published public private(set) var isCompleted = false
    /// 视频轨道应用方向变换后的尺寸；没有视频轨道或尚未准备时为零。
    @Published public private(set) var videoSize: CGSize = .zero
    /// 视频轨道的方向，用于后台切换时正确展示暂存的画面。
    public private(set) var videoTransform: CGAffineTransform = .identity
    /// 当前资源准备失败或播放器项目报告失败。
    @Published public private(set) var didFail = false
    /// 对应 Flutter 的 `controller.value.duration`，`prepare()` 之后才有值。
    @Published public private(set) var duration: TimeInterval = 0

    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var itemStatusObserver: NSKeyValueObservation?
    private var playbackStatusObserver: NSKeyValueObservation?
    private let loops: Bool
    /// 始终保留初始来源，包括非延迟加载模式，以便 reset 后重新准备。
    private let sourceURL: URL?
    private let urlResolver: (String) -> URL?
    private let preview: Bool
    private let log: (String, Error?) -> Void
    private var isDisposed = false
    /// 调用方希望继续播放；等待缓冲时可为 true，而 isPlaying 仍为 false。
    @Published public private(set) var wantsPlayback = false
    /// 标识当前播放器项目的生命周期；reset/dispose 后旧准备任务不得再更新状态。
    private var generation = UUID()
    private let playbackIntent = VideoPlaybackIntent()

    /// 创建播放器。defersLoading 为 true 时先不关联资源，由 prepare 按需创建项目。
    /// 这样页面转场期间可以先完成布局，再加载资源和启动播放。
    public init(url: String, muted: Bool = true, loops: Bool = false, defersLoading: Bool = false, urlResolver: @escaping (String) -> URL? = { URL(string: $0) }, preview: Bool = false, log: @escaping (String, Error?) -> Void = { _, _ in }) {
        self.loops = loops
        self.urlResolver = urlResolver
        self.preview = preview
        self.log = log
        let source = VideoPlaybackController.parseSource(url, urlResolver: urlResolver)
        sourceURL = source
        if preview {
            player = AVPlayer()
            return
        }
        // 通话页先创建空播放器，转场完成并异步读取媒体信息后再关联视频资源。
        if !defersLoading, let source {
            player = AVPlayer(url: source)
        } else {
            player = AVPlayer()
        }
        player.isMuted = muted
        player.actionAtItemEnd = loops ? .none : .pause
        if source == nil && !defersLoading { didFail = true }
        // 调用 play() 只表示发出请求；通过 timeControlStatus 区分实际播放与缓冲。
        // 回到主线程后重新读取当前状态，避免排队的旧 KVO 值覆盖新状态。
        playbackStatusObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isDisposed else { return }
                self.isPlaying = self.wantsPlayback && self.player.timeControlStatus == .playing
            }
        }
        if let item = player.currentItem { observeEnd(of: item) }
    }

    /// 支持远程 URL、file URL 和本地文件路径；空值及没有主机的 HTTP 地址返回 nil。
    /// 绝对路径须先按文件处理，因为 URL(string:) 可以把它解释为非文件的相对 URL。
    public static func parseSource(_ raw: String, urlResolver: (String) -> URL? = { URL(string: $0) }) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("/") { return URL(fileURLWithPath: value) }
        guard let url = URL(string: value) else { return nil }
        guard let scheme = url.scheme else { return URL(fileURLWithPath: value) }
        if ["http", "https"].contains(scheme.lowercased()) {
            guard url.host?.isEmpty == false else { return nil }
            return urlResolver(value)
        }
        return url
    }

    /// 观察当前项目失败和播放结束。更换项目之前应先移除旧观察者。
    private func observeEnd(of item: AVPlayerItem) {
        guard endObserver == nil else { return }
        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, !self.isDisposed, self.player.currentItem === item else { return }
                self.didFail = true
                self.wantsPlayback = false
                self.isPlaying = false
                self.log("player item failed", item.error)
            }
        }
        // 通知排队后，用户可能暂停、重播、重试或离开页面；同时校验项目、资源代次
        // 和通知到达时的播放意图，确保旧回调不能修改新一轮播放。
        let observedGeneration = generation
        let playbackIntent = playbackIntent
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, !self.isDisposed,
                      self.generation == observedGeneration, self.player.currentItem === item else { return }
                self.playbackIntent.advance()
                self.player.pause()
                self.didFail = true
                self.wantsPlayback = false
                self.isPlaying = false
                self.log("player item failed during playback", nil)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self, weak item] _ in
            let observedIntent = playbackIntent.current()
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, !self.isDisposed,
                      self.wantsPlayback, playbackIntent.current() == observedIntent,
                      self.generation == observedGeneration, self.player.currentItem === item else { return }
                if self.loops {
                    // seek 本身也是异步操作，完成后必须再次校验，才能安全地继续循环。
                    self.player.seek(to: .zero) { [weak self, weak item] finished in
                        Task { @MainActor [weak self, weak item] in
                            guard finished, let self, let item, !self.isDisposed, self.wantsPlayback,
                                  playbackIntent.current() == observedIntent, self.generation == observedGeneration,
                                  self.player.currentItem === item else { return }
                            self.player.play()
                        }
                    }
                } else {
                    self.wantsPlayback = false
                    self.isCompleted = true
                    self.isPlaying = false
                }
            }
        }
    }

    /// 异步读取时长和视频尺寸，必要时创建并关联播放器项目。
    /// - Parameter urlOverride: 当前没有项目时优先使用的来源，可用于准备已下载的本地文件。
    /// 取消、重置或销毁发生后，旧任务的结果和错误都不会写回当前状态。
    public func prepare(urlOverride: URL? = nil) async {
        guard !isDisposed, !preview else { return }
        let preparationGeneration = generation
        let asset: AVAsset
        if let urlOverride, player.currentItem == nil {
            let normalized = urlResolver(urlOverride.absoluteString) ?? urlOverride
            asset = AVURLAsset(url: normalized)
        } else if let item = player.currentItem {
            asset = item.asset
        } else if let sourceURL {
            asset = AVURLAsset(url: sourceURL)
        } else { didFail = true; return }
        do {
            let assetDuration = try await asset.load(.duration)
            try Task.checkCancellation()
            guard !isDisposed, generation == preparationGeneration else { return }
            duration = assetDuration.seconds.isFinite ? assetDuration.seconds : 0
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                // naturalSize 可能未包含旋转信息，需要应用轨道变换得到展示方向的尺寸。
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                try Task.checkCancellation()
                guard !isDisposed, generation == preparationGeneration else { return }
                let transformed = size.applying(transform)
                videoTransform = transform
                videoSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
            }
            try Task.checkCancellation()
            guard !isDisposed, generation == preparationGeneration else { return }
            if player.currentItem == nil {
                let item = AVPlayerItem(asset: asset)
                player.replaceCurrentItem(with: item)
                observeEnd(of: item)
            }
        } catch is CancellationError {
            return
        } catch {
            if !isDisposed, generation == preparationGeneration, !Task.isCancelled {
                didFail = true
                log("asset preparation failed", error)
            }
        }
    }

    /// 为重试清除当前项目、观察者和显示状态，同时保留初始 sourceURL。
    /// 已在执行的 prepare、完成通知和 seek 回调会因版本变化而失效。
    public func resetForRetry() {
        guard !isDisposed else { return }
        generation = UUID()
        playbackIntent.advance()
        wantsPlayback = false
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver); self.failureObserver = nil }
        player.pause()
        player.replaceCurrentItem(with: nil)
        didFail = false
        isPlaying = false
        isCompleted = false
        duration = 0
        videoSize = .zero
        videoTransform = .identity
    }

    /// 发起播放请求；实际播放可能因缓冲延后，通过 isPlaying 观察结果。
    public func play() {
        guard !preview else { return }
        guard !didFail, !isDisposed, player.currentItem != nil else { return }
        playbackIntent.advance()
        wantsPlayback = true
        player.play()
        isPlaying = player.timeControlStatus == .playing
    }

    /// 等待当前项目可播放；项目替换、失败、任务取消、销毁或超时均返回 false。
    /// readyToPlay 只表示资源已准备，不代表播放器已进入实际播放状态。
    public func waitUntilReady(timeout: Duration = .seconds(15)) async -> Bool {
        guard let item = player.currentItem else { return false }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            guard !isDisposed, !Task.isCancelled, player.currentItem === item else { return false }
            switch item.status {
            case .readyToPlay: return true
            case .failed: return false
            default: break
            }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return false }
        }
        return false
    }

    /// 等待播放器实际进入 playing；用于必须等到视频播放后才能继续的流程。
    /// 期间若项目被替换、失败、任务取消、销毁或超时，返回 false。
    public func waitUntilPlaying(timeout: Duration = .seconds(15)) async -> Bool {
        guard let item = player.currentItem else { return false }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            guard !isDisposed, !Task.isCancelled, player.currentItem === item, item.status != .failed else { return false }
            if player.timeControlStatus == .playing { return true }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return false }
        }
        return false
    }

    /// 暂停并撤销播放意图，使此前排队的结束通知或循环 seek 无法重新启动播放。
    public func pause() {
        playbackIntent.advance()
        wantsPlayback = false
        player.pause()
        isPlaying = false
    }

    /// 清除完成状态，从起点重新发起播放。
    public func replay() {
        guard !didFail, !isDisposed else { return }
        isCompleted = false
        player.seek(to: .zero)
        play()
    }

    /// 永久结束控制器：撤销异步结果，移除观察者并断开播放器项目。
    /// 销毁后不再接受准备或播放请求；需要重试时应使用 resetForRetry。
    public func dispose() {
        isDisposed = true
        playbackIntent.advance()
        wantsPlayback = false
        generation = UUID()
        playbackStatusObserver?.invalidate()
        playbackStatusObserver = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            self.failureObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
    }
}

// MARK: - 播放视图

/// `AVPlayerLayer` 的 SwiftUI 包装。
public struct VideoSurface: UIViewRepresentable {
    public init(player: AVPlayer, preservesFrameOnBackground: Bool = false, videoTransform: CGAffineTransform = .identity, onFirstFrameReady: (() -> Void)? = nil) {
        self.player = player; self.preservesFrameOnBackground = preservesFrameOnBackground
        self.videoTransform = videoTransform; self.onFirstFrameReady = onFirstFrameReady
    }
    let player: AVPlayer
    var preservesFrameOnBackground = false
    var videoTransform: CGAffineTransform = .identity
    var onFirstFrameReady: (() -> Void)?

    @MainActor
    public final class Coordinator {
        var onFirstFrameReady: (() -> Void)?
        weak var view: VideoPlayerView?
        var observation: NSKeyValueObservation?
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> VideoPlayerView {
        let view = VideoPlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        view.configureBackgroundFrame(enabled: preservesFrameOnBackground, transform: videoTransform)
        context.coordinator.view = view
        context.coordinator.onFirstFrameReady = onFirstFrameReady
        if onFirstFrameReady != nil {
            context.coordinator.observation = view.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) {
                [weak coordinator = context.coordinator, weak view] layer, _ in
                guard layer.isReadyForDisplay else { return }
                Task { @MainActor [weak coordinator, weak view] in
                    guard let coordinator, let view, coordinator.view === view,
                          view.playerLayer.isReadyForDisplay else { return }
                    coordinator.onFirstFrameReady?()
                }
            }
        }
        return view
    }

    public func updateUIView(_ uiView: VideoPlayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        context.coordinator.onFirstFrameReady = onFirstFrameReady
        uiView.configureBackgroundFrame(enabled: preservesFrameOnBackground, transform: videoTransform)
    }

    public static func dismantleUIView(_ view: VideoPlayerView, coordinator: Coordinator) {
        coordinator.view = nil
        coordinator.observation?.invalidate()
        coordinator.observation = nil
        view.stopBackgroundFrameProtection()
    }
}

public final class VideoPlayerView: UIView {
    public override class var layerClass: AnyClass { AVPlayerLayer.self }

    public var playerLayer: AVPlayerLayer {
        // swiftlint:disable:next force_cast
        layer as! AVPlayerLayer
    }

    private var videoOutput: AVPlayerItemVideoOutput?
    private weak var outputItem: AVPlayerItem?
    private var frameView: UIImageView?
    private var displayLink: CADisplayLink?
    private var foregroundStartedAt: CFTimeInterval = 0
    private var foregroundFrameReady = false
    private var videoTransform: CGAffineTransform = .identity
    private let imageContext = CIContext()

    /// 仅 AIA 通话启用：缓存仍留在受保护的业务窗口内，不进入后台遮罩窗口。
    func configureBackgroundFrame(enabled: Bool, transform: CGAffineTransform) {
        guard enabled, let item = playerLayer.player?.currentItem else {
            stopBackgroundFrameProtection()
            return
        }
        videoTransform = transform
        guard outputItem !== item else { return }
        stopBackgroundFrameProtection()
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        outputItem = item
        videoOutput = output
        NotificationCenter.default.addObserver(self, selector: #selector(captureBackgroundFrame),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(waitForForegroundFrame),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc public func captureBackgroundFrame() {
        displayLink?.invalidate()
        displayLink = nil
        guard let output = videoOutput else { return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        let image = CIImage(cvPixelBuffer: buffer).transformed(by: videoTransform)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else { return }
        let still = frameView ?? UIImageView(frame: bounds)
        still.frame = bounds
        still.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        still.contentMode = .scaleAspectFill
        still.clipsToBounds = true
        still.isUserInteractionEnabled = false
        still.image = UIImage(cgImage: cgImage)
        if still.superview == nil { addSubview(still) }
        frameView = still
    }

    @objc public func waitForForegroundFrame() {
        guard frameView != nil else { return }
        displayLink?.invalidate()
        foregroundStartedAt = CACurrentMediaTime()
        foregroundFrameReady = false
        let link = CADisplayLink(target: self, selector: #selector(checkForegroundFrame))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func checkForegroundFrame() {
        guard let output = videoOutput else { removeBackgroundFrame(); return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        // 新视频帧和图层均已就绪后再恢复显示；超时则避免异常时永久停留在旧画面。
        if CACurrentMediaTime() - foregroundStartedAt > 3 {
            removeBackgroundFrame()
        } else if foregroundFrameReady {
            // 多等一次屏幕刷新，让播放器图层有机会提交已解码的新画面。
            removeBackgroundFrame()
        } else if playerLayer.isReadyForDisplay && output.hasNewPixelBuffer(forItemTime: time) {
            foregroundFrameReady = true
        }
    }

    private func removeBackgroundFrame() {
        displayLink?.invalidate()
        displayLink = nil
        frameView?.removeFromSuperview()
        frameView = nil
    }

    func stopBackgroundFrameProtection() {
        NotificationCenter.default.removeObserver(self)
        removeBackgroundFrame()
        if let output = videoOutput { outputItem?.remove(output) }
        videoOutput = nil
        outputItem = nil
    }
}
