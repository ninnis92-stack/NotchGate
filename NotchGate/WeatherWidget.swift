import CoreLocation
import SwiftUI

struct DayForecast: Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let high: Double
    let low: Double
    let symbol: String
}

struct WeatherSnapshot: Equatable {
    let temperature: Double
    let condition: String
    let symbol: String
    let location: String
    let high: Double?
    let low: Double?
    let days: [DayForecast]
}

@Observable
final class WeatherService: NSObject, CLLocationManagerDelegate {
    var snapshot: WeatherSnapshot?
    var statusText = "Locating…"

    private let manager = CLLocationManager()
    private var started = false
    private var lastLocation: CLLocation?
    private var refreshTimer: Timer?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorizationNotDetermined: Bool {
        manager.authorizationStatus == .notDetermined
    }

    var authorizationDenied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    func start() {
        guard !started else { return }
        started = true
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let location = self.lastLocation {
                Task { await self.fetch(from: location) }
            } else if self.hasLocationAuthorization {
                self.manager.requestLocation()
            }
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
        requestLocationIfAllowed()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        started = false
    }

    /// Called once during Pro onboarding. Glance views never initiate permission prompts.
    func requestAccessIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            requestLocationIfAllowed()
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
        lastLocation = location
        Task { await fetch(from: location) }
    }

    private func fetch(from location: CLLocation) async {
        let locale = Locale(identifier: "en_US_POSIX")
        let latitude = String(format: "%.2f", locale: locale, location.coordinate.latitude)
        let longitude = String(format: "%.2f", locale: locale, location.coordinate.longitude)
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: latitude),
            URLQueryItem(name: "longitude", value: longitude),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: "celsius")
        ]
        guard let url = components?.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let code = decoded.current.weather_code
            let place = await reverseGeocode(location)
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
                days: days
            )
        } catch {
            statusText = "Weather unavailable"
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
                Button {
                    layout.temperatureUnit.toggle()
                } label: {
                    Text(layout.temperatureUnit.formatted(snapshot.temperature))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                .help("Switch \(layout.temperatureUnit == .celsius ? "to Fahrenheit" : "to Celsius")")
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
    }
}
