import Dispatch
import Foundation

/// A type that determines when `ValueObservation` notifies its fresh values.
///
/// ## Topics
///
/// ### Built-In Schedulers
///
/// - ``async(onQueue:)``
/// - ``immediate``
/// - ``AsyncValueObservationScheduler``
/// - ``ImmediateValueObservationScheduler``
public protocol ValueObservationScheduler: Sendable {
    /// Returns whether the initial value should be immediately notified.
    ///
    /// If the result is true, then this method was called on the main thread.
    func immediateInitialValue() -> Bool
    
#if compiler(<6.0) && !hasFeature(TransferringArgsAndResults)
    func schedule(_ action: @escaping @Sendable () -> Void)
#else
    func schedule(_ action: transferring @escaping () -> Void)
#endif
}

extension ValueObservationScheduler {
#if compiler(<6.0) && !hasFeature(TransferringArgsAndResults)
    func scheduleInitial(_ action: @escaping @Sendable () -> Void) {
        if immediateInitialValue() {
            action()
        } else {
            schedule(action)
        }
    }
#else
    func scheduleInitial(_ action: transferring @escaping () -> Void) {
        if immediateInitialValue() {
            action()
        } else {
            schedule(action)
        }
    }
#endif
}

// MARK: - AsyncValueObservationScheduler

/// A scheduler that asynchronously notifies fresh value of a `DispatchQueue`.
public struct AsyncValueObservationScheduler: ValueObservationScheduler {
    var queue: DispatchQueue
    
    public init(queue: DispatchQueue) {
        self.queue = queue
    }
    
    public func immediateInitialValue() -> Bool { false }
    
#if compiler(<6.0) && !hasFeature(TransferringArgsAndResults)
    public func schedule(_ action: @escaping @Sendable () -> Void) {
        queue.async(execute: action)
    }
#else
    public func schedule(_ action: transferring @escaping () -> Void) {
        queue.async(execute: action)
    }
#endif
}

extension ValueObservationScheduler where Self == AsyncValueObservationScheduler {
    /// A scheduler that asynchronously notifies fresh value of the
    /// given `DispatchQueue`.
    ///
    /// For example:
    ///
    /// ```swift
    /// let observation = ValueObservation.tracking { db in
    ///     try Player.fetchAll(db)
    /// }
    ///
    /// let cancellable = try observation.start(
    ///     in: dbQueue,
    ///     scheduling: .async(onQueue: .main),
    ///     onError: { error in ... },
    ///     onChange: { (players: [Player]) in
    ///         print("fresh players: \(players)")
    ///     })
    /// ```
    ///
    /// - warning: Make sure you provide a serial queue, because a
    ///   concurrent one such as `DispachQueue.global(qos: .default)` would
    ///   mess with the ordering of fresh value notifications.
    public static func async(onQueue queue: DispatchQueue) -> AsyncValueObservationScheduler {
        AsyncValueObservationScheduler(queue: queue)
    }
}

// MARK: - ImmediateValueObservationScheduler

/// A scheduler that notifies all values on the main `DispatchQueue`. The
/// first value is immediately notified when the `ValueObservation`
/// is started.
public struct ImmediateValueObservationScheduler: ValueObservationScheduler, Sendable {
    public init() { }
    
    public func immediateInitialValue() -> Bool {
        GRDBPrecondition(
            Thread.isMainThread,
            "ValueObservation must be started from the main thread.")
        return true
    }
    
#if compiler(<6.0) && !hasFeature(TransferringArgsAndResults)
    public func schedule(_ action: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async(execute: action)
    }
#else
    public func schedule(_ action: transferring @escaping () -> Void) {
        // DispatchQueue does not accept a transferring closure yet, as
        // discussed at <https://forums.swift.org/t/how-can-i-use-region-based-isolation/71426/5>.
        // So let's wrap the closure in a Sendable wrapper.
        let action = UncheckedSendableWrapper(value: action)
        
        DispatchQueue.main.async {
            action.value()
        }
    }
#endif
}

extension ValueObservationScheduler where Self == ImmediateValueObservationScheduler {
    /// A scheduler that notifies all values on the main `DispatchQueue`. The
    /// first value is immediately notified when the `ValueObservation`
    /// is started.
    ///
    /// For example:
    ///
    /// ```swift
    /// let observation = ValueObservation.tracking { db in
    ///     try Player.fetchAll(db)
    /// }
    ///
    /// let cancellable = try observation.start(
    ///     in: dbQueue,
    ///     scheduling: .immediate,
    ///     onError: { error in ... },
    ///     onChange: { (players: [Player]) in
    ///         print("fresh players: \(players)")
    ///     })
    /// // <- here "fresh players" is already printed.
    /// ```
    ///
    /// - important: this scheduler requires that the observation is started
    ///  from the main queue. A fatal error is raised otherwise.
    public static var immediate: ImmediateValueObservationScheduler {
        ImmediateValueObservationScheduler()
    }
}
