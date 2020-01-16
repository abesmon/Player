//
//  PlayerLayerView.swift
//  Pods
//
//  Originaly Created by BrikerMan on 16/4/28.
//  Modified by SMG Team
//
//

import UIKit
import AVFoundation

private class Timer {
    private var block: (() -> Void)!
    private let interval: TimeInterval

    private var resumed = false

    init(interval: TimeInterval, block: @escaping () -> Void) {
        self.block = block
        self.interval = interval
    }

    private func runNext() {
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let this = self, this.resumed else { return }
            this.fireEvent()
        }
    }

    private func fireEvent() {
        block()
        runNext()
    }

    func resume() {
        resumed = true
        fireEvent()
    }

    func pause() {
        resumed = false
    }

    deinit {
        resumed = false
        block = nil
    }
}

/**
 Player status emun

 - notSetURL:      not set url yet
 - readyToPlay:    player ready to play
 - buffering:      player buffering
 - bufferFinished: buffer finished
 - playedToTheEnd: played to the End
 - error:          error with playing
 */
public enum PlayerState {
    case notSetURL
    case readyToPlay
    case buffering
    case bufferFinished
    case playedToTheEnd
    case error
}

/**
 video aspect ratio types

 - `default`:    video default aspect
 - sixteen2NINE: 16:9
 - four2THREE:   4:3
 */
public enum PlayerAspectRatio: Int {
    case `default`    = 0
    case sixteen2NINE
    case four2THREE
}

/// Делегат, позволяющий реагировать на события плеера
public protocol PlayerLayerViewDelegate: AnyObject {

    /// Уведомляет о смене статуса плеера
    ///
    /// - Parameters:
    ///   - player: экземпляр плеера
    ///   - state: Собственно новое состояние плеера
    func player(player: PlayerLayerView, playerStateDidChange state: PlayerState)

    /// Уведомляет о состоянии загрузки контента, которое можно использовать, например, для отображения на шкале времени
    ///
    /// - Parameters:
    ///   - player: экземпляр плеера
    ///   - loadedDuration: сколько загружено времени
    ///   - totalDuration: общая продолжительность трека
    func player(player: PlayerLayerView, loadedTimeDidChange loadedDuration: TimeInterval, totalDuration: TimeInterval)

    /// Уведомляет о текущей позиции проигрывания
    ///
    /// - Parameters:
    ///   - player: экземпляр плеера
    ///   - currentTime: текущее время
    ///   - totalTime: общая продолжительность трека
    func player(player: PlayerLayerView, playTimeDidChange currentTime: TimeInterval, totalTime: TimeInterval)

    /// Уведомляет о смене статуса проигрывания "проигрывание/пауза"
    ///
    /// - Parameters:
    ///   - player: экземпляр плеера
    ///   - playing: статус "проигрывание/пауза"
    func player(player: PlayerLayerView, playerIsPlaying playing: Bool)

    /// Уведомляет об изменении скорости загрузки контента. Можно использовать для переключения качества
    ///
    /// - Parameters:
    ///   - player: экземпляр плеера
    ///   - oldBitrate: старое значение
    ///   - newBitrate: новое значение битрейта
    func player(player: PlayerLayerView, bitrateChangedFrom oldBitrate: Double, to newBitrate: Double)
}

private var staticLastBitrate = 0.0
/// Вьюха-плеер, которая позволяет проигрывать видео и настраивать различные события
open class PlayerLayerView: UIView {

    /// Делегат, который отрабатывает разные события
    public weak var delegate: PlayerLayerViewDelegate?

    public var seekTime = 0

    public var playerItem: AVPlayerItem? {
        didSet {
            onPlayerItemChange()
        }
    }

    public lazy var player: AVPlayer? = {
        if let item = self.playerItem {
            let player = AVPlayer(playerItem: item)
            return player
        }
        return nil
    }()

    public var videoGravity = AVLayerVideoGravity.resizeAspect {
        didSet {
            self.playerLayer?.videoGravity = videoGravity
        }
    }

    /// Текущее состояния проигрывания
    public var isPlaying: Bool = false {
        didSet {
            if oldValue != isPlaying {
                delegate?.player(player: self, playerIsPlaying: isPlaying)
            }
        }
    }

    var aspectRatio: PlayerAspectRatio = .default {
        didSet {
            self.setNeedsLayout()
        }
    }

    private lazy var timer = Timer(interval: 0.5) { [weak self] in self?.playerTimerAction() }

    fileprivate var urlAsset: AVURLAsset?

    fileprivate var lastPlayerItem: AVPlayerItem?
    /// playerLayer
    fileprivate var playerLayer: AVPlayerLayer?
    #if os(iOS)
    /// 音量滑杆
    fileprivate var volumeViewSlider: UISlider!
    #endif
    /// 播放器的几种状态
    fileprivate var state = PlayerState.notSetURL {
        didSet {
            if state != oldValue {
                delegate?.player(player: self, playerStateDidChange: state)
            }
        }
    }
    /// 是否为全屏
    fileprivate var isFullScreen  = false
    /// 是否锁定屏幕方向
    fileprivate var isLocked      = false
    /// 是否在调节音量
    fileprivate var isVolume      = false
    /// 是否播放本地文件
    fileprivate var isLocalVideo  = false
    /// slider上次的值
    fileprivate var sliderLastValue: Float = 0
    /// 是否点了重播
    fileprivate var repeatToPlay  = false
    /// 播放完了
    fileprivate var playDidEnd    = false
    // playbackBufferEmpty会反复进入，因此在bufferingOneSecond延时播放执行完之前再调用bufferingSomeSecond都忽略
    // 仅在bufferingSomeSecond里面使用
    fileprivate var isBuffering     = false
    fileprivate var hasReadyToPlay  = false
    // 1 - time to seek to, 2 - seek completion callback
    fileprivate var shouldSeekTo: (TimeInterval,(() -> Void)?)?

    private(set) var lastBitrate: Double {
        get { return staticLastBitrate }
        set { staticLastBitrate = newValue }
    }

    /// Описывает действия, которые будут происходить при проигрывании трека
    public var pointsHandlers = [TrackAction]()

    // MARK: - observe handlers
    @objc private func playItemEvent() {
        guard let event = playerItem?.accessLog()?.events.last else { return }
        let oldBitrate = lastBitrate
        let newBitrate = event.observedBitrate / 1000.0
        lastBitrate = newBitrate
        delegate?.player(player: self, bitrateChangedFrom: oldBitrate, to: newBitrate)
    }

    // MARK: - Actions

    /// Проигрывает контент по URLу
    ///
    /// - Parameter url: путь, где лежит трек
    public func playURL(url: URL) {
        let asset = AVURLAsset(url: url)
        playAsset(asset: asset)

        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(playItemEvent),
                                       name: NSNotification.Name.AVPlayerItemNewAccessLogEntry,
                                       object: playerItem)
    }

    /// Аналогично `playURL()`, только используется низкоуровневый ассет
    ///
    /// - Parameter asset: ассет для проигрывания
    public func playAsset(asset: AVURLAsset) {
        urlAsset = asset
        onSetVideoAsset()
        play()
    }

    /// Продолжает проигрывание трека
    public func play() {
        if let player = player {
            player.play()
            timer.resume()
            isPlaying = true
        }
    }

    /// Ставит плеер на паузу
    public func pause() {
        player?.pause()
        isPlaying = false
        timer.pause()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override open func layoutSubviews() {
        super.layoutSubviews()
        switch self.aspectRatio {
        case .default:
            self.playerLayer?.videoGravity = AVLayerVideoGravity.resizeAspect
            self.playerLayer?.frame  = self.bounds
            break
        case .sixteen2NINE:
            self.playerLayer?.videoGravity = AVLayerVideoGravity.resize
            self.playerLayer?.frame = CGRect(x: 0, y: 0, width: self.bounds.width, height: self.bounds.width/(16/9))
            break
        case .four2THREE:
            self.playerLayer?.videoGravity = AVLayerVideoGravity.resize
            let _w = self.bounds.height * 4 / 3
            self.playerLayer?.frame = CGRect(x: (self.bounds.width - _w )/2, y: 0, width: _w, height: self.bounds.height)
            break
        }
    }

    /// Сбрасывает состояние плеера
    public func resetPlayer() {
        // 初始化状态变量
        self.playDidEnd = false
        self.playerItem = nil
        self.seekTime   = 0

        self.timer.pause()

        self.pause()
        // 移除原来的layer
        self.playerLayer?.removeFromSuperlayer()
        // 替换PlayerItem为nil
        self.player?.replaceCurrentItem(with: nil)
        player?.removeObserver(self, forKeyPath: "rate")

        // 把player置为nil
        self.player = nil
    }

    /// Функция, которую стоит вызывать перед завершением работы с плеером - плеер завершит свою работу, освободив ресурсы
    public func prepareToDeinit() {
        self.resetPlayer()
    }

    func onTimeSliderBegan() {
        if self.player?.currentItem?.status == AVPlayerItem.Status.readyToPlay {
            self.timer.pause()
        }
    }

    /// Перематывает плеер на нужную позицию
    ///
    /// - Parameters:
    ///   - secounds: целевое время
    ///   - completion: колбек, который будет вызван, когда процесс перемотки завершится
    public func seek(to seconds: TimeInterval, completion:(() -> Void)? = nil) {
        guard !seconds.isNaN else { return }
        timer.resume()
        if player?.currentItem?.status == AVPlayerItem.Status.readyToPlay {
            let draggedTime = CMTime(value: Int64(seconds), timescale: 1)
            player!.seek(to: draggedTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero, completionHandler: { (_) in
                completion?()
            })
        } else {
            shouldSeekTo = (seconds, completion)
        }
    }

    // MARK: - 设置视频URL
    fileprivate func onSetVideoAsset() {
        repeatToPlay = false
        playDidEnd   = false
        configPlayer()
    }

    fileprivate func onPlayerItemChange() {
        guard lastPlayerItem != playerItem else { return }

        if let item = lastPlayerItem {
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: item)
            item.removeObserver(self, forKeyPath: "status")
            item.removeObserver(self, forKeyPath: "loadedTimeRanges")
            item.removeObserver(self, forKeyPath: "playbackBufferEmpty")
            item.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
        }

        lastPlayerItem = playerItem

        if let item = playerItem {
            NotificationCenter.default.addObserver(self, selector: #selector(moviePlayDidEnd),
                                                   name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                                   object: playerItem)

            item.addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions.new, context: nil)
            item.addObserver(self, forKeyPath: "loadedTimeRanges", options: NSKeyValueObservingOptions.new, context: nil)
            item.addObserver(self, forKeyPath: "playbackBufferEmpty", options: NSKeyValueObservingOptions.new, context: nil)
            item.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: NSKeyValueObservingOptions.new, context: nil)
        }
    }

    fileprivate func configPlayer() {
        player?.removeObserver(self, forKeyPath: "rate")
        playerItem = AVPlayerItem(asset: urlAsset!)
        player     = AVPlayer(playerItem: playerItem!)
        player!.addObserver(self, forKeyPath: "rate", options: NSKeyValueObservingOptions.new, context: nil)

        playerLayer?.removeFromSuperlayer()
        playerLayer = AVPlayerLayer(player: player)
        playerLayer!.videoGravity = videoGravity

        layer.addSublayer(playerLayer!)

        setNeedsLayout()
        layoutIfNeeded()
    }

    // MARK: - 计时器事件
    @objc fileprivate func playerTimerAction() {
        guard let playerItem = playerItem else { return }

        if playerItem.duration.timescale != 0 {
            let currentTime = CMTimeGetSeconds(self.player!.currentTime())
            let totalTime   = TimeInterval(playerItem.duration.value) / TimeInterval(playerItem.duration.timescale)
            delegate?.player(player: self, playTimeDidChange: currentTime, totalTime: totalTime)
            pointsHandlers.process(time: currentTime)
        }
        updateStatus(includeLoading: true)
    }

    fileprivate func updateStatus(includeLoading: Bool = false) {
        if let player = player {
            if let playerItem = playerItem, includeLoading {
                if playerItem.isPlaybackLikelyToKeepUp || playerItem.isPlaybackBufferFull {
                    self.state = .bufferFinished
                } else if playerItem.status == .failed {
                    self.state = .error
                } else {
                    self.state = .buffering
                }
            }
            if player.rate == 0.0 {
                if player.error != nil {
                    self.state = .error
                    return
                }
                if let currentItem = player.currentItem {
                    if player.currentTime() >= currentItem.duration {
                        moviePlayDidEnd()
                        return
                    }
                    if currentItem.isPlaybackLikelyToKeepUp || currentItem.isPlaybackBufferFull {

                    }
                }
            }
        }
    }

    // MARK: - Notification Event
    @objc fileprivate func moviePlayDidEnd() {
        if state != .playedToTheEnd {
            if let playerItem = playerItem {
                let currentTime = CMTimeGetSeconds(playerItem.duration)
                delegate?.player(player: self,
                                 playTimeDidChange: currentTime,
                                 totalTime: CMTimeGetSeconds(playerItem.duration))
                pointsHandlers.process(time: currentTime)
            }

            self.state = .playedToTheEnd
            self.isPlaying = false
            self.playDidEnd = true
            self.timer.pause()
        }
    }

    // MARK: - KVO
    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if let item = object as? AVPlayerItem, let keyPath = keyPath {
            if item == self.playerItem {
                switch keyPath {
                case "status":
                    if item.status == .failed || player?.status == AVPlayer.Status.failed {
                        self.state = .error
                    } else if player?.status == AVPlayer.Status.readyToPlay {
                        self.state = .buffering
                        if let shouldSeekTo = shouldSeekTo {
                            seek(to: shouldSeekTo.0, completion: { [weak self] in
                                shouldSeekTo.1?()
                                self?.shouldSeekTo = nil
                                self?.hasReadyToPlay = true
                                self?.state = .readyToPlay
                            })
                        } else {
                            self.hasReadyToPlay = true
                            self.state = .readyToPlay
                        }
                    }

                case "loadedTimeRanges":
                    // 计算缓冲进度
                    if let timeInterVarl    = self.availableDuration() {
                        let duration        = item.duration
                        let totalDuration   = CMTimeGetSeconds(duration)
                        delegate?.player(player: self, loadedTimeDidChange: timeInterVarl, totalDuration: totalDuration)
                    }

                case "playbackBufferEmpty":
                    // 当缓冲是空的时候
                    if self.playerItem!.isPlaybackBufferEmpty {
                        self.state = .buffering
                        self.bufferingSomeSecond()
                    }
                case "playbackLikelyToKeepUp":
                    if item.isPlaybackBufferEmpty {
                        if state != .bufferFinished && hasReadyToPlay {
                            self.state = .bufferFinished
                            self.playDidEnd = true
                        }
                    }
                default:
                    break
                }
            }
        }

        if keyPath == "rate" {
            updateStatus()
        }
    }

    /**
     缓冲进度

     - returns: 缓冲进度
     */
    fileprivate func availableDuration() -> TimeInterval? {
        if let loadedTimeRanges = player?.currentItem?.loadedTimeRanges,
            let first = loadedTimeRanges.first {

            let timeRange = first.timeRangeValue
            let startSeconds = CMTimeGetSeconds(timeRange.start)
            let durationSecound = CMTimeGetSeconds(timeRange.duration)
            let result = startSeconds + durationSecound
            return result
        }
        return nil
    }

    /**
     缓冲比较差的时候
     */
    fileprivate func bufferingSomeSecond() {
        self.state = .buffering
        // playbackBufferEmpty会反复进入，因此在bufferingOneSecond延时播放执行完之前再调用bufferingSomeSecond都忽略

        if isBuffering {
            return
        }
        isBuffering = true
        // 需要先暂停一小会之后再播放，否则网络状况不好的时候时间在走，声音播放不出来
        player?.pause()
        let popTime = DispatchTime.now() + Double(Int64( Double(NSEC_PER_SEC) * 1.0 )) / Double(NSEC_PER_SEC)

        DispatchQueue.main.asyncAfter(deadline: popTime) {

            // 如果执行了play还是没有播放则说明还没有缓存好，则再次缓存一段时间
            self.isBuffering = false
            if let item = self.playerItem {
                if !item.isPlaybackLikelyToKeepUp {
                    self.bufferingSomeSecond()
                } else {
                    // 如果此时用户已经暂停了，则不再需要开启播放了
                    self.state = PlayerState.bufferFinished
                }
            }
        }
    }
}
