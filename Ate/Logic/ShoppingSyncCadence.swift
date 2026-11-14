import Foundation

/// Visible Shopping only; no background execution or instantaneous realtime claim.
enum ShoppingSyncCadence {
    /// Preserve local edit order even when several changes share one clock ms.
    static func nextStamp(now: Double, prior: Double) -> Double {
        max(now.rounded(), prior.rounded() + 1)
    }

    static func seconds(consecutiveFailures: Int) -> UInt64 {
        let exponent = min(max(consecutiveFailures, 0), 4)
        return min(30 * (UInt64(1) << exponent), 300)
    }
}
