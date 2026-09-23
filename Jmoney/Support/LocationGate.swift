import Foundation
import CoreLocation

/// Pure location-tagging rules — the testable half of the port of
/// `app/add-transaction.tsx`'s location feature. The framework calls live in
/// `LocationService` (the `BiometricGate`/`BiometricService` split).
///
/// The source's capture strategy, preserved:
/// * permission is requested first; a denial disables the toggle and reports an error;
/// * a *last known* position is used immediately as the fast fallback;
/// * then a progressive-accuracy ladder (High 10 s → Balanced 10 s → Low 5 s)
///   races each rung against its timeout until a fresh fix lands;
/// * if every rung fails but a last-known fix was captured, the last-known fix
///   is kept — the source only clears the location on total failure.
enum LocationGate {
    /// One rung of the progressive-accuracy ladder.
    struct Rung: Equatable {
        let accuracy: CLLocationAccuracy
        let timeout: TimeInterval
        /// The source's `name` field, used only in its timeout error message.
        let name: String
    }

    /// The source's ladder, verbatim: High 10 s, Balanced 10 s, Low 5 s.
    static let ladder: [Rung] = [
        Rung(accuracy: kCLLocationAccuracyBest, timeout: 10, name: "High"),
        Rung(accuracy: kCLLocationAccuracyNearestTenMeters, timeout: 10, name: "Medium"),
        Rung(accuracy: kCLLocationAccuracyKilometer, timeout: 5, name: "Low"),
    ]

    /// Where a displayed fix came from — the source's `locationSource` strings.
    enum FixSource: String {
        case current = "Current"
        case lastKnown = "Last Known"
    }

    /// A captured coordinate pair.
    struct Fix: Equatable {
        var latitude: Double
        var longitude: Double
        var source: FixSource
    }

    /// `LocationEditSheet`'s manual entry: "lat, lng", exactly two comma-separated
    /// numbers, whitespace tolerated. `parseFloat` + `isNaN` on the source side —
    /// so trailing garbage after a number is *accepted* there (`parseFloat("12abc")`
    /// is `12`), and `Double` substring parsing reproduces that only for the
    /// leading-number case; anything that does not parse to a number fails.
    static func parseManualCoordinates(_ text: String) -> (latitude: Double, longitude: Double)? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1])
        else { return nil }
        return (latitude, longitude)
    }

    /// The editor's new-mode row and the edit row show four decimals
    /// (`toFixed(4)`); the edit row's resting text uses six (`toFixed(6)`).
    static func display(_ latitude: Double, _ longitude: Double, digits: Int) -> String {
        String(format: "%.\(digits)f, %.\(digits)f", latitude, longitude)
    }

    /// The Google Maps deep link both the row's context menu and the editor use.
    static func mapsURL(latitude: Double, longitude: Double) -> URL? {
        URL(string: "https://www.google.com/maps/search/?api=1&query=\(latitude),\(longitude)")
    }
}
