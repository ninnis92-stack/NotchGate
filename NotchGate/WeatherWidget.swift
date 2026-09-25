import CoreLocation
import SwiftUI

struct DayForecast: Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let high: Double
    let low: Double
    let symbol: String
}

struct WeatherSnapshot: Codable, Equatable {
    let temperature: Double
    let condition: String
    let symbol: String
    let location: String
    let high: Double?
    let low: Double?
    let days: [DayForecast]
    let updatedAt: Date
}

@Observable
@MainActor
final class WeatherService: NSObject, CLLocationManagerDelegate {
    var snapshot: WeatherSnapshot?
    var statusText = "Locating…"

    private let manager = CLLocationManager()
    private var started = false
    private var lastLocation: CLLocation?
    private var refreshTimer: Timer?
    private var fetchGeneration = 0
    private let cacheKey = "notch.weather.snapshot"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(WeatherSnapshot.self, from: data) {
            snapshot = cached
            statusText = "Using last update"
        }
    }

    var needsLocationPermission: Bool {
        switch manager.authorizationStatus {
        case .notDetermined, .denied, .restricted: return true
        default: return false
        }
    }

    var locationAccessDenied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
    }

    func start(promptForPermission: Bool = false) {
        guard !started else { return }
        started = true
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let location = self.lastLocation {
                    await self.fetch(from: location)
                } else if self.hasLocationAuthorization {
                    self.manager.requestLocation()
                }
            }
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
        requestLocationIfAllowed()
        if promptForPermission && needsLocationPermission && !locationAccessDenied {
            requestAccessFromUser()
        }
    }

    func refresh() {
        if locationAccessDenied {
            openSettings()
        } else if needsLocationPermission {
            requestAccessFromUser()
        } else if let lastLocation {
            Task { await fetch(from: lastLocation) }
        } else {
            requestLocationIfAllowed()
        }
    }

    /// Request location only after the user interacts with Weather.
    func requestAccessFromUser() {
        manager.requestWhenInUseAuthorization()
        if hasLocationAuthorization {
            manager.requestLocation()
        }
    }

    private var hasLocationAuthorization: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }

    private func requestLocationIfAllowed() {
        guard hasLocationAuthorization else {
            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                statusText = "Location access needed"
            }
            return
        }
        statusText = "Locating…"
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestLocationIfAllowed()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == kCLErrorDomain, nsError.code == CLError.locationUnknown.rawValue {
            return
        }
        if nsError.domain == kCLErrorDomain, nsError.code == CLError.denied.rawValue {
            statusText = "Location access needed"
            return
        }
        statusText = "Weather unavailable"
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Weather only needs an approximate area. Keep the location sent to
        // Open-Meteo and the geocoder to roughly 1 km precision.
        let coordinate = location.coordinate
        let approximate = CLLocation(
            latitude: (coordinate.latitude * 100).rounded() / 100,
            longitude: (coordinate.longitude * 100).rounded() / 100
        )
        lastLocation = approximate
        Task { await fetch(from: approximate) }
    }

    private func fetch(from location: CLLocation) async {
        fetchGeneration += 1
        let generation = fetchGeneration
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: "celsius")
        ]
        guard let url = components?.url else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let code = decoded.current.weather_code
            let place = await reverseGeocode(location)
            guard generation == fetchGeneration else { return }
            let days = decoded.daily.map { daily -> [DayForecast] in
                zip(daily.time.indices, daily.time).compactMap { index, day in
                    guard daily.weather_code.indices.contains(index),
                          daily.temperature_2m_max.indices.contains(index),
                          daily.temperature_2m_min.indices.contains(index) else {
                        return nil
                    }
                    let date = DateFormatter.yearMonthDay.date(from: day)
                        ?? ISO8601DateFormatter.truncated.date(from: day)
                        ?? Date()
                    return DayForecast(
                        date: date,
                        high: daily.temperature_2m_max[index],
                        low: daily.temperature_2m_min[index],
                        symbol: WeatherCode.symbol(daily.weather_code[index])
                    )
                }
            } ?? []
            snapshot = WeatherSnapshot(
                temperature: decoded.current.temperature_2m,
                condition: WeatherCode.label(code),
                symbol: WeatherCode.symbol(code),
                location: place,
                high: days.first?.high,
                low: days.first?.low,
                days: days,
                updatedAt: Date()
            )
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
            statusText = "Updated just now"
        } catch {
            statusText = snapshot == nil ? "Weather unavailable" : "Using last update"
        }
    }

    private func reverseGeocode(_ location: CLLocation) async -> String {
        await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { marks, _ in
                let name = marks?.first?.locality ?? marks?.first?.administrativeArea ?? "Local"
                continuation.resume(returning: name)
            }
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
    }

    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
    }

    let current: Current
    let daily: Daily?
}

private extension ISO8601DateFormatter {
    static let truncated: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}

private extension DateFormatter {
    static let yearMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private enum WeatherCode {
    static func label(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: return "Rain"
        case 71, 73, 75, 85, 86: return "Snow"
        case 95, 96, 99: return "Storms"
        default: return "Mixed"
        }
    }

    static func symbol(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.fill"
        default: return "cloud.fill"
        }
    }
}

struct WeatherWidget: View {
    var service: WeatherService
    var accent: Color

    @Environment(NotchCustomization.self) private var layout

    var body: some View {
        HStack(spacing: 8) {
            if let snapshot = service.snapshot {
                Image(systemName: snapshot.symbol)
                    .foregroundStyle(accent)
                    .frame(width: 16)
                    .layoutPriority(1)
                Text(snapshot.location)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(0)
                Spacer(minLength: 8)
                Text(layout.temperatureUnit.formatted(snapshot.temperature))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                Text(snapshot.condition)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
            } else {
                Image(systemName: "cloud.sun.fill")
                    .foregroundStyle(accent)
                    .frame(width: 16)
                Text("Weather")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("—")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help("Open Weather details")
    }
}
