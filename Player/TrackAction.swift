//
// Created by horovodovodo4ka on 21.08.2018.
//

import Foundation

/// Описывает, каким образом и когда выполняется действие
public enum TrackAction {
    /// действие `action` будет выполнено один раз, когда текущее время станет больше, чем `when`. Удобно использовать, когда событие сработать должно даже если была перемотка, а не воспроизведение само дошло до этого времени.
    case once(when: Double, action: () -> Void)
    /// действие `action` будет выполнено один раз, когда текущее время станет больше, чем `when`. Учитывает, насколько далеко находится целевое время от текущей отметки (параметр `precision`). Это позволяет более точно контролировать события - вызывать их только когда событие рядом с текущим временем.
    case oncePrecise(when: Double, precision: Double, action: () -> Void)
    /// действие срабатывает неограниченное количество раз. На вход колбека передается текущее время.
    case any(action: (Double) -> Void)

    fileprivate func process(time: Double) -> Bool {
        switch self {
        case .once(let targetTime, let action):
            guard targetTime <= time else { return true }
            action()
            return false
        case .oncePrecise(let targetTime, let delta, let action):
            guard  (targetTime...targetTime + delta).contains(time) else { return true }
            action()
            return false
        case .any(let action):
            action(time)
            return true
        }
    }
}

extension Array where Element == TrackAction {
    mutating func process(time: Double) {
        guard !time.isNaN else { return }
        if let unlock = Guard.lock(self) {
            self = filter { $0.process(time: time) }
            unlock()
        }
    }
}
