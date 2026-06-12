import Foundation

/// Builds Apple Maps deep links (maps:// opens the Maps app directly).
public enum MapLink {

    public static func url(for place: Place) -> URL {
        var components = URLComponents()
        components.scheme = "maps"
        components.host = ""
        if let lat = place.latitude, let lon = place.longitude {
            components.queryItems = [
                URLQueryItem(name: "ll", value: "\(lat),\(lon)"),
                URLQueryItem(name: "q", value: place.name)
            ]
        } else {
            let query = place.query.isEmpty ? place.name : place.query
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        // URLComponents percent-encodes query values; force-unwrap is safe.
        return components.url!
    }
}
