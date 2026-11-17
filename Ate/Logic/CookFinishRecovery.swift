/// Recovery is initiated only by a named user action and consumed after its presentation dismisses.
/// Repeated dismissal callbacks cannot repeat a Finish or set aside saved data.
struct CookFinishRecovery {
    enum Action: Equatable { case retry, setAside }
    private var pending: Action?
    mutating func request(_ action: Action) { pending = action }
    mutating func consume() -> Action? {
        defer { pending = nil }
        return pending
    }
}
