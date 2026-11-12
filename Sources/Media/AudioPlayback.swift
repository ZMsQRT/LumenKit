import AVFoundation
import Foundation

/// 将代理回调中的播放器引用传回主线程。
/// AVAudioPlayer 本身不声明 Sendable；回调线程只包装并保留引用，
/// 播放器的状态读取和操作仍由 AudioPlayback 在主线程完成。
private struct AudioPlayerReference: @unchecked Sendable {
    let player: AVAudioPlayer
}

// MARK: - 音频播放

/// 管理本组件创建的多个播放器对系统音频会话的共同使用。
///
/// AVAudioSession 是进程级对象，而不是每个播放器独立的对象。第一个持有者
/// 激活会话，最后一个持有者释放时才尝试停用，避免一个播放器结束时打断另一个。
/// 此协调器只跟踪 AudioPlayback，不代表能识别所有第三方 SDK 的会话使用。
@MainActor
public final class AudioSessionCoordinator {
    public static let shared = AudioSessionCoordinator()
    private var owners: Set<UUID> = []
    private let activate: () throws -> Void
    private let deactivate: () -> Void

    public init(activate: @escaping () throws -> Void = {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true)
    }, deactivate: @escaping () -> Void = {
        let session = AVAudioSession.sharedInstance()
        // 若类别或模式已被其他组件改变，跳过停用，避免关闭它们设置的会话。
        // 相同类别和选项无法证明会话仍由本组件独占，因此这里是尽力保护。
        guard session.category == .playback, session.mode == .default,
              session.categoryOptions.contains(.duckOthers) else { return }
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }) {
        self.activate = activate
        self.deactivate = deactivate
    }

    /// 同一 owner 重复申请是幂等的；激活失败时不会加入持有者集合。
    public func acquire(_ owner: UUID) throws {
        guard !owners.contains(owner) else { return }
        if owners.isEmpty { try activate() }
        owners.insert(owner)
    }

    /// 未持有或重复释放时无操作；仅最后一个持有者负责停用会话。
    public func release(_ owner: UUID) {
        guard owners.remove(owner) != nil, owners.isEmpty else { return }
        deactivate()
    }
}

/// Bundle 音频播放器，用于铃声、挂断音和匹配页音乐。
/// 循环播放使用 AVAudioPlayer 的 `numberOfLoops = -1`。播放失败只记录日志
/// 并返回 false，不抛出错误，避免音效问题阻断业务流程。
@MainActor
open class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private let sessionOwner = UUID()
    private let session: AudioSessionCoordinator
    private let resourceResolver: (String) -> URL?
    private let preview: Bool
    private let log: (String, Error?) -> Void

    public init(session: AudioSessionCoordinator? = nil, resourceResolver: @escaping (String) -> URL? = { Bundle.main.url(forResource: $0, withExtension: nil) }, preview: Bool = false, log: @escaping (String, Error?) -> Void = { _, _ in }) {
        self.session = session ?? .shared
        self.resourceResolver = resourceResolver
        self.preview = preview
        self.log = log
        super.init()
    }

    deinit {
        // 调用方未显式 stop 时兜底释放。协调器受主线程隔离，因此异步回到主线程。
        let session = session
        let owner = sessionOwner
        Task { @MainActor in session.release(owner) }
    }

    public var isPlaying: Bool { player?.isPlaying ?? false }
    public var duration: TimeInterval { player?.duration ?? 0 }

    /// 播放一个 bundle 内音频。
    /// - Parameters:
    ///   - path: bundle 相对路径。
    ///   - loops: `true` 时无限循环（来电铃声），`false` 播完即止（挂断音）。
    ///   - volume: 播放音量，遵循 AVAudioPlayer 的 0...1 范围。
    /// - Returns: 成功启动播放器时为 true；预览、资源缺失或播放失败时为 false。
    @discardableResult
    public func play(_ path: String, loops: Bool = false, volume: Float = 1) -> Bool {
        guard !preview else { return false }
        // 每次切换音频先结束旧播放，避免旧代理回调影响新的持有关系。
        stop()
        guard let url = resourceResolver(path) else {
            log("missing audio: \(path)", nil)
            return false
        }
        do {
            // 先构造播放器再申请会话，资源不可解码时不改变系统音频会话。
            let player = try AVAudioPlayer(contentsOf: url)
            try session.acquire(sessionOwner)
            player.numberOfLoops = loops ? -1 : 0
            player.volume = volume
            player.delegate = self
            self.player = player
            player.prepareToPlay()
            guard player.play() else { stop(); return false }
            return true
        } catch {
            stop()
            log("play failed: \(path)", error)
            return false
        }
    }

    /// 停止当前音频并释放本实例的会话持有权；多次调用安全。
    public func stop() {
        player?.stop()
        player = nil
        session.release(sessionOwner)
    }

    /// 保留给现有调用方的释放入口，实际与 stop 使用同一套持有权逻辑。
    public func deactivateSession() {
        stop()
    }

    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let reference = AudioPlayerReference(player: player)
        Task { @MainActor [weak self] in
            // 播放器可能已被替换；只允许当前播放器的回调释放当前会话。
            guard let self, self.player === reference.player else { return }
            self.stop()
        }
    }

    public nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let reference = AudioPlayerReference(player: player)
        Task { @MainActor [weak self] in
            guard let self, self.player === reference.player else { return }
            self.stop()
        }
    }
}
