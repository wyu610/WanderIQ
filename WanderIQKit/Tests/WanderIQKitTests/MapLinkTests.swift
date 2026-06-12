import Testing
import Foundation
@testable import WanderIQKit

@Suite struct MapLinkTests {

    @Test func coordinatePlaceUsesLatLon() {
        let place = Place(name: "上海天文馆", query: "上海天文馆", latitude: 30.9, longitude: 121.9)
        let url = MapLink.url(for: place)
        #expect(url.scheme == "maps")
        #expect(url.absoluteString.contains("ll=30.9,121.9"))
        #expect(url.absoluteString.contains("q="))
    }

    @Test func queryOnlyPlaceFallsBackToSearch() {
        let place = Place(name: "Peak Tram", query: "Peak Tram Hong Kong")
        let url = MapLink.url(for: place)
        #expect(url.absoluteString.contains("q=Peak%20Tram%20Hong%20Kong"))
        #expect(!url.absoluteString.contains("ll="))
    }

    @Test func emptyQueryUsesName() {
        let place = Place(name: "沙面岛", query: "")
        let url = MapLink.url(for: place)
        #expect(url.absoluteString.contains("q=%E6%B2%99%E9%9D%A2%E5%B2%9B"))
    }
}
