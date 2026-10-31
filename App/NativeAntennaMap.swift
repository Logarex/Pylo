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
        // A query completing during a pinch must not mutate annotations or overlays.
        if !coordinator.moving { coordinator.applyStations(map); coordinator.scheduleDirections(map) }
    }
    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.refreshTask?.cancel()
        map.delegate = nil
        map.removeOverlays(map.overlays)
    }
    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeAntennaMap
        var annotations: [String: StationAnnotation] = [:]
        var stationIDs: Set<String> = []
        var commandID: UUID?
        var moving = false
        var refreshTask: Task<Void, Never>?
        var orientationOverlay: OrientationOverlay?
        var renderedArrows: [OrientationArrow] = []
        var imageCache: [String: UIImage] = [:]
        init(_ parent: NativeAntennaMap) { self.parent = parent }
        func applyStations(_ map: MKMapView) {
            let ids = Set(parent.stations.map(\.id))
            guard ids != stationIDs else { return }
            let removed = annotations.filter { !ids.contains($0.key) }
            map.removeAnnotations(Array(removed.values))
            for key in removed.keys { annotations.removeValue(forKey: key) }
            let added = parent.stations.filter { annotations[$0.id] == nil }.map(StationAnnotation.init)
            for annotation in added { annotations[annotation.station.id] = annotation }
            map.addAnnotations(added)
            stationIDs = ids
        }
        func scheduleDirections(_ map: MKMapView) {
            refreshTask?.cancel()
            if !parent.showDirections {
                if let orientationOverlay { map.removeOverlay(orientationOverlay) }
                orientationOverlay = nil; renderedArrows = []
                return
            }
            refreshTask = Task { @MainActor [weak self, weak map] in
                try? await Task.sleep(for: .milliseconds(360))
                guard !Task.isCancelled, let self, let map, !self.moving else { return }
                // Dense groups need zooming in first, rather than dozens of overlapping arrows.
                let visible = self.annotations.values.filter { annotation in
                    guard map.visibleMapRect.contains(MKMapPoint(annotation.coordinate)),
                          let view = map.view(for: annotation) else { return false }
                    return view.superview != nil && !view.isHidden && view.alpha > 0.1
                }.map(\.station)
                let arrows = OrientationPlan.make(stations: visible, directions: self.parent.directions, latitude: map.centerCoordinate.latitude, longitude: map.centerCoordinate.longitude)
                if arrows == self.renderedArrows, let overlay = self.orientationOverlay, overlay.boundingMapRect.contains(map.visibleMapRect) {
                    map.renderer(for: overlay)?.alpha = 1
                    return
                }
                if let old = self.orientationOverlay { map.removeOverlay(old) }
                self.renderedArrows = arrows
                self.orientationOverlay = nil
                guard !arrows.isEmpty else { return }
                let overlay = OrientationOverlay(arrows: arrows, rect: map.visibleMapRect)
                self.orientationOverlay = overlay
                map.addOverlay(overlay, level: .aboveRoads)
            }
        }
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            moving = true; refreshTask?.cancel()
            if let orientationOverlay { mapView.renderer(for: orientationOverlay)?.alpha = 0 }
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            moving = false
            applyStations(mapView)
            scheduleDirections(mapView)
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
            guard let orientations = overlay as? OrientationOverlay else { return MKOverlayRenderer(overlay: overlay) }
            return OrientationRenderer(overlay: orientations)
        }
        private func clusterImage(_ members: [Station]) -> UIImage {
            let groups = Dictionary(grouping: members, by: \.operatorName).mapValues(\.count)
            let names = groups.keys.sorted()
            let key = String(UIScreen.main.traitCollection.userInterfaceStyle.rawValue) + names.map { "\($0):\(groups[$0] ?? 0)" }.joined(separator: "|")
            if let cached = imageCache[key] { return cached }
            let image = UIGraphicsImageRenderer(size: CGSize(width: 44,height: 44)).image { context in
                let circle = CGRect(x: 2,y: 2,width: 40,height: 40)
                UIColor.secondarySystemGroupedBackground.setFill(); context.cgContext.fillEllipse(in: circle)
                var start = -Double.pi/2
                for name in names {
                    let end = start + Double(groups[name] ?? 0) / Double(max(1,members.count)) * 2 * .pi
                    context.cgContext.setStrokeColor(UIColor(Palette.operatorColor(name)).cgColor)
                    context.cgContext.setLineWidth(5)
                    context.cgContext.addArc(center: CGPoint(x:22,y:22), radius:19,startAngle:start,endAngle:end,clockwise:false)
                    context.cgContext.strokePath(); start = end
                }
                let text = NSAttributedString(string: String(members.count),attributes:[.font:UIFont.systemFont(ofSize:14,weight:.bold),.foregroundColor:UIColor.label])
                let size = text.size(); text.draw(at:CGPoint(x:22-size.width/2,y:22-size.height/2))
            }
            if imageCache.count >= 200 { imageCache.removeAll(keepingCapacity: true) }
            imageCache[key] = image
            return image
        }
    }
}

/// One lightweight layer; arrow length stays constant on screen instead of expanding on zoom.
final class OrientationOverlay: NSObject, MKOverlay {
    let arrows: [OrientationArrow]
    let boundingMapRect: MKMapRect
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate }
    init(arrows: [OrientationArrow], rect: MKMapRect) { self.arrows = arrows; boundingMapRect = rect.insetBy(dx: -rect.width * 0.1, dy: -rect.height * 0.1) }
}
final class OrientationRenderer: MKOverlayRenderer {
    private let arrows: [OrientationArrow]
    private let colors: [CGColor]
    init(overlay: OrientationOverlay) {
        arrows = overlay.arrows
        colors = overlay.arrows.map { UIColor(Palette.operatorColor($0.operatorName)).cgColor }
        super.init(overlay: overlay)
    }
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard zoomScale.isFinite, zoomScale > 0 else { return }
        let scale = 1 / zoomScale
        context.setLineWidth(1.6 * scale)
        context.setLineCap(.round); context.setLineJoin(.round)
        let length = 30 * scale, head = 5 * scale, inset = 10 * scale
        for (index, arrow) in arrows.enumerated() {
            let origin = point(for: MKMapPoint(CLLocationCoordinate2D(latitude: arrow.latitude, longitude: arrow.longitude)))
            let radians = arrow.azimuth * .pi / 180
            let dx = sin(radians), dy = -cos(radians)
            let start = CGPoint(x: origin.x + dx * inset, y: origin.y + dy * inset)
            let end = CGPoint(x: start.x + dx * length, y: start.y + dy * length)
            context.setStrokeColor(colors[index])
            context.move(to: start); context.addLine(to: end)
            context.move(to: CGPoint(x: end.x - dx * head + dy * head * 0.6, y: end.y - dy * head - dx * head * 0.6))
            context.addLine(to: end)
            context.addLine(to: CGPoint(x: end.x - dx * head - dy * head * 0.6, y: end.y - dy * head + dx * head * 0.6))
            context.strokePath()
        }
    }
}
