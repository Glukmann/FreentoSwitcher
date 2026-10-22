import CoreGraphics

/// Перехват клавиатурных событий через CGEventTap (полная реализация — Task 10).
/// Здесь — общий маркер собственных синтезированных событий (A18), который
/// EventSynth ставит в `eventSourceUserData`, чтобы tap не подхватывал их повторно.
public final class EventTap: @unchecked Sendable {
    /// Mark for our own synthesized events so we don't re-ingest them.
    static let ownEventUserData: Int64 = 0xF3E9A11

    public init() {}
}
