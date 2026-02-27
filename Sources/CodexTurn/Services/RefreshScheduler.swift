import Foundation

@MainActor
final class RefreshScheduler {
    private var timer: Timer?
    private var interval: TimeInterval = AppConstants.defaultPollSeconds
    private var tickHandler: (() -> Void)?

    deinit {
        timer?.invalidate()
    }

    func configure(
        interval: TimeInterval,
        fireImmediately: Bool = true,
        tick: @escaping () -> Void
    ) {
        self.interval = interval
        tickHandler = tick
        restart(fireImmediately: fireImmediately)
    }

    func restart(fireImmediately: Bool = true) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [handler = tickHandler] _ in
            handler?()
        }
        if fireImmediately {
            timer?.fire()
        }
    }
}
