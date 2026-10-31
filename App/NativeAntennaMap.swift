import SwiftUI
import MapKit

struct MapCommand {
    let id = UUID()
    let region: MKCoordinateRegion
}
final class StationAnnotation: NSObject, MKAnnotation {
    let station: Station
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude) }
    var title: String? { operatorDisplayName(station.operatorName) }
    init(_ station: Station) { self.station = station }
}
/// UIKit owns gestures, annotation reuse and clustering; SwiftUI only submits data after interaction.
struct NativeAntennaMap: UIViewRepresentable {
    let initialRegion: MKCoordinateRegion
    let stations: [Station]
    let directions: [String: [Double]]
    let showDirections: Bool
    let command: MapCommand?
    let onRegion: (MKCoordinateRegion) -> Void
    let onSelection: ([Station]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.setRegion(initialRegion, animated: false)
        map.isZoomEnabled = true; map.isScrollEnabled = true; map.isRotateEnabled = true; map.isPitchEnabled = true
        map.showsUserLocation = true; map.showsCompass = true; map.showsScale = true
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "station")
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if let command, command.id != coordinator.commandID {
            coordinator.commandID = command.id
            map.setRegion(command.region, animated: true)
        }
        let ids = Set(stations.map(\.id))
        if ids != coordinator.stationIDs {
            let removed = coordinator.annotations.filter { !ids.contains($0.key) }
            map.removeAnnotations(Array(removed.values))
            for key in removed.keys { coordinator.annotations.removeValue(forKey: key) }
            let added = stations.filter { coordinator.annotations[$0.id] == nil }.map(StationAnnotation.init)
            for annotation in added { coordinator.annotations[annotation.station.id] = annotation }
            map.addAnnotations(added)
            coordinator.stationIDs = ids
        }
        // One overlay per operator, only a small set of nearby stations. Never rebuild during a gesture.
        let directionKey = showDirections ? stations.prefix(24).map { $0.id + (directions[$0.id] ?? []).map(String.init(describing:)).joined(separator: ",") }.joined(separator: "|") : ""
        if coordinator.directionKey != directionKey {
            coordinator.directionKey = directionKey
            map.removeOverlays(map.overlays)
            guard showDirections else { return }
            let grouped = Dictionary(grouping: stations.prefix(24), by: \.operatorName)
            for (name, values) in grouped {
                let lines = values.flatMap { station in
                    (directions[station.id] ?? []).map { azimuth in
                        MKPolyline(coordinates: arrow(station, azimuth), count: 5)
                    }
                }
                if !lines.isEmpty {
                    let overlay = MKMultiPolyline(lines); overlay.title = name
                    map.addOverlay(overlay, level: .aboveRoads)
                }
            }
        }
    }
    private func arrow(_ station: Station, _ azimuth: Double) -> [CLLocationCoordinate2D] {
        let start = CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)
        func offset(_ origin: CLLocationCoordinate2D, _ angle: Double, _ km: Double) -> CLLocationCoordinate2D {
            let radians = angle * .pi / 180
            return CLLocationCoordinate2D(latitude: origin.latitude + cos(radians)*km/111.32, longitude: origin.longitude + sin(radians)*km/(111.32*max(0.05,cos(origin.latitude * .pi/180))))
        }
        let end = offset(start,azimuth,0.25)
        return [start,end,offset(end,azimuth+150,0.065),end,offset(end,azimuth-150,0.065)]
    }
    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeAntennaMap
        var annotations: [String: StationAnnotation] = [:]
        var stationIDs: Set<String> = []
        var commandID: UUID?
        var directionKey = ""
        init(_ parent: NativeAntennaMap) { self.parent = parent }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            Task { @MainActor [weak self] in self?.parent.onRegion(region) }
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: cluster)
                let members = cluster.memberAnnotations.compactMap { ($0 as? StationAnnotation)?.station }
                view.image = clusterImage(members); view.displayPriority = .defaultHigh
                view.accessibilityLabel = "\(members.count) stations : \(Set(members.map { operatorDisplayName($0.operatorName) }).sorted().joined(separator: ", "))"
                return view
            }
            guard let station = annotation as? StationAnnotation,
                  let view = mapView.dequeueReusableAnnotationView(withIdentifier: "station", for: station) as? MKMarkerAnnotationView else { return nil }
            view.clusteringIdentifier = "stations"
            view.markerTintColor = UIColor(Palette.operatorColor(station.station.operatorName))
            view.glyphImage = UIImage(systemName: "antenna.radiowaves.left.and.right")
            view.glyphTintColor = .white
            view.titleVisibility = .hidden; view.subtitleVisibility = .hidden
            view.displayPriority = .defaultLow
            view.accessibilityLabel = "\(operatorDisplayName(station.station.operatorName)) · \(station.station.address)"
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
            let members: [Station]
            if let cluster = annotation as? MKClusterAnnotation { members = cluster.memberAnnotations.compactMap { ($0 as? StationAnnotation)?.station } }
            else if let station = annotation as? StationAnnotation { members = [station.station] }
            else { return }
            parent.onSelection(members.sorted { $0.operatorName < $1.operatorName })
            mapView.deselectAnnotation(annotation, animated: false)
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let lines = overlay as? MKMultiPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKMultiPolylineRenderer(multiPolyline: lines)
            renderer.strokeColor = UIColor(Palette.operatorColor(lines.title ?? ""))
            renderer.lineWidth = 5; renderer.lineCap = .round; renderer.lineJoin = .round
            return renderer
        }
        private func clusterImage(_ members: [Station]) -> UIImage {
            let names = Array(Set(members.map(\.operatorName))).sorted()
            return UIGraphicsImageRenderer(size: CGSize(width: 44,height: 44)).image { context in
                let circle = CGRect(x: 2,y: 2,width: 40,height: 40)
                UIColor.secondarySystemGroupedBackground.setFill(); context.cgContext.fillEllipse(in: circle)
                var start = -Double.pi/2
                for name in names {
                    let end = start + Double(members.filter { $0.operatorName == name }.count) / Double(max(1,members.count)) * 2 * .pi
                    context.cgContext.setStrokeColor(UIColor(Palette.operatorColor(name)).cgColor)
                    context.cgContext.setLineWidth(5)
                    context.cgContext.addArc(center: CGPoint(x:22,y:22), radius:19,startAngle:start,endAngle:end,clockwise:false)
                    context.cgContext.strokePath(); start = end
                }
                let text = NSAttributedString(string: String(members.count),attributes:[.font:UIFont.systemFont(ofSize:14,weight:.bold),.foregroundColor:UIColor.label])
                let size = text.size(); text.draw(at:CGPoint(x:22-size.width/2,y:22-size.height/2))
            }
        }
    }
}
