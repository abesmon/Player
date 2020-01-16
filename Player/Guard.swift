//
//  ExecutionGuard.swift
//  sealine
//
//  Created by Anna Sidorova on 20.01.17.
//  Copyright © 2017 SL Tech. All rights reserved.
//

import UIKit

/// Class for guarding execution recursion.
public final class Guard {
    public typealias LockType = Int

    private static var locks = Set<LockType>()

    private let tag: LockType

    /// Initialize guard with tag
    ///
    /// - Parameters:
    ///   - tag: Unique tag for guard
    private init(_ tag: LockType) {
        self.tag = tag
    }

    public static func lock(_ tag: LockType) -> (() -> Void)? {
        return Guard(tag).lock()
    }

    public static func lock(_ tag: String) -> (() -> Void)? {
        return Guard(tag.hashValue).lock()
    }

    public static func lock<T>(_ tag: T) -> (() -> Void)? {
        return Guard(unsafeBitCast(tag, to: Int.self)).lock()
    }

    /// Wraps code execution in tagged block and lock it from recursion. For unlocking called block **must** call *unlock* parameter.
    ///
    /// - Parameter block: Execution guard block - first parameter is block which unlocks quard
    /// - Returns: returns unlocking function
    private func lock() -> (() -> Void)? {
        guard !Guard.locks.contains(tag) else { return nil }

        Guard.locks.insert(tag)

        return unlock
    }

    /// Must be called to unlock guard
    private func unlock() {
        Guard.locks.remove(tag)
    }
}
