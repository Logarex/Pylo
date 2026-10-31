import Foundation
public struct OrientationArrow: Equatable, Sendable {
    public let stationID: String
    public let latitude: Double
    public let longitude: Double
    public let operatorName: String
    public let azimuth: Double
}
/// Hard rendering budget, independent of how many ANFR directions the source contains.
public enum OrientationPlan {
    public static let maximumStations = 12
    public static let maximumArrows = 48
    public static func make(stations: [Station], directions: [String: [Double]], latitude: Double, longitude: Double) -> [OrientationArrow] {
        let longitudeScale = cos(latitude * .pi / 180)
        func distance(_ station: Station) -> Double { pow(station.latitude-latitude,2) + pow((station.longitude-longitude)*longitudeScale,2) }
        let nearest = stations.filter { !(directions[$0.id] ?? []).isEmpty }.sorted { distance($0) < distance($1) }.prefix(maximumStations)
        var result: [OrientationArrow] = []
        for station in nearest {
            for azimuth in Array(Set(directions[station.id] ?? [])).filter({ $0.isFinite && (0..<360).contains($0) }).sorted().prefix(6) {
                guard result.count < maximumArrows else { return result }
                result.append(OrientationArrow(stationID: station.id, latitude: station.latitude, longitude: station.longitude, operatorName: station.operatorName, azimuth: azimuth))
            }
        }
        return result
    }
}
