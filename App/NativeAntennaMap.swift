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
        let directionsLayer = OrientationLayer()
        directionsLayer.translatesAutoresizingMaskIntoConstraints = false
        map.addSubview(directionsLayer)
        NSLayoutConstraint.activate([
            directionsLayer.leadingAnchor.constraint(equalTo: map.leadingAnchor),
            directionsLayer.trailingAnchor.constraint(equalTo: map.trailingAnchor),
            directionsLayer.topAnchor.constraint(equalTo: map.topAnchor),
            directionsLayer.bottomAnchor.constraint(equalTo: map.bottomAnchor)
        ])
        context.coordinator.directionsLayer = directionsLayer
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "station")
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.appearance != map.traitCollection.userInterfaceStyle {
            coordinator.appearance = map.traitCollection.userInterfaceStyle
            coordinator.imageCache.removeAll(keepingCapacity: true)
            for annotation in map.annotations {
                if let cluster = annotation as? MKClusterAnnotation, let view = map.view(for: cluster) {
                    view.image = coordinator.clusterImage(cluster.memberAnnotations.compactMap { ($0 as? StationAnnotation)?.station }, traits: map.traitCollection)
                }
            }
        }
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
        coordinator.directionsLayer?.removeFromSuperview()
    }
    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeAntennaMap
        var annotations: [String: StationAnnotation] = [:]
        var appliedStations: [Station] = []
        var commandID: UUID?
        var moving = false
        var refreshTask: Task<Void, Never>?
        weak var directionsLayer: OrientationLayer?
        var imageCache: [String: UIImage] = [:]
        var appearance: UIUserInterfaceStyle = .unspecified
        init(_ parent: NativeAntennaMap) { self.parent = parent }
        func applyStations(_ map: MKMapView) {
            guard parent.stations != appliedStations else { return }
            let desired = Dictionary(uniqueKeysWithValues: parent.stations.map { ($0.id, $0) })
            let removed = annotations.filter { desired[$0.key] != $0.value.station }
            map.removeAnnotations(Array(removed.values))
            for key in removed.keys { annotations.removeValue(forKey: key) }
            let added = parent.stations.filter { annotations[$0.id] == nil }.map(StationAnnotation.init)
            for annotation in added { annotations[annotation.station.id] = annotation }
            map.addAnnotations(added)
            appliedStations = parent.stations
        }
        func scheduleDirections(_ map: MKMapView) {
            refreshTask?.cancel()
            if !parent.showDirections {
                directionsLayer?.arrows = []
                directionsLayer?.isHidden = true
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
                guard let layer = self.directionsLayer else { return }
                layer.arrows = arrows.compactMap { arrow in
                    guard let annotation = self.annotations[arrow.stationID], let view = map.view(for: annotation) else { return nil }
                    // Anchor to the round head of the marker, not the pin tip underneath it.
                    let anchor = view.convert(CGPoint(x: view.bounds.midX, y: min(view.bounds.midY, view.bounds.minY + view.bounds.width / 2)), to: layer)
                    let coordinate = annotation.coordinate
                    let radians = arrow.azimuth * .pi / 180
                    let reference = CLLocationCoordinate2D(latitude: coordinate.latitude + cos(radians)*0.001, longitude: coordinate.longitude + sin(radians)*0.001/max(0.05,cos(coordinate.latitude * .pi/180)))
                    let origin = map.convert(coordinate, toPointTo: layer)
                    let projected = map.convert(reference, toPointTo: layer)
                    let dx = projected.x-origin.x, dy = projected.y-origin.y
                    let magnitude = hypot(dx,dy)
                    guard magnitude.isFinite, magnitude > 0 else { return nil }
                    let ux = dx/magnitude, uy = dy/magnitude
                    return ScreenOrientation(start: CGPoint(x: anchor.x+ux*21,y: anchor.y+uy*21), end: CGPoint(x: anchor.x+ux*51,y: anchor.y+uy*51), color: UIColor(Palette.operatorColor(arrow.operatorName)))
                }
                layer.isHidden = false
                map.bringSubviewToFront(layer)
            }
        }
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            moving = true; refreshTask?.cancel()
            directionsLayer?.isHidden = true
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
                view.image = clusterImage(members, traits: mapView.traitCollection); view.displayPriority = .defaultHigh
                view.accessibilityLabel = "\(members.count) stations : \(Set(members.map { operatorDisplayName($0.operatorName) }).sorted().joined(separator: ", "))"
                return view
            }
            guard let station = annotation as? StationAnnotation,
                  let view = mapView.dequeueReusableAnnotationView(withIdentifier: "station", for: station) as? MKMarkerAnnotationView else { return nil }
            view.clusteringIdentifier = "stations"
            view.markerTintColor = UIColor(Palette.operatorColor(station.station.operatorName))
            view.glyphImage = UIImage(systemName: "antenna.radiowaves.left.and.right")
            view.glyphTintColor = station.station.operatorName.contains("FREE") ? UIColor { $0.userInterfaceStyle == .dark ? .black : .white } : .white
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
        func clusterImage(_ members: [Station], traits: UITraitCollection) -> UIImage {
            let groups = Dictionary(grouping: members, by: \.operatorName).mapValues(\.count)
            let names = groups.keys.sorted()
            let key = String(traits.userInterfaceStyle.rawValue) + names.map { "\($0):\(groups[$0] ?? 0)" }.joined(separator: "|")
            if let cached = imageCache[key] { return cached }
            let image = UIGraphicsImageRenderer(size: CGSize(width: 44,height: 44)).image { context in
                let circle = CGRect(x: 2,y: 2,width: 40,height: 40)
                UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits).setFill(); context.cgContext.fillEllipse(in: circle)
                var start = -Double.pi/2
                for name in names {
                    let end = start + Double(groups[name] ?? 0) / Double(max(1,members.count)) * 2 * .pi
                    context.cgContext.setStrokeColor(UIColor(Palette.operatorColor(name)).resolvedColor(with: traits).cgColor)
                    context.cgContext.setLineWidth(5)
                    context.cgContext.addArc(center: CGPoint(x:22,y:22), radius:19,startAngle:start,endAngle:end,clockwise:false)
                    context.cgContext.strokePath(); start = end
                }
                let text = NSAttributedString(string: String(members.count),attributes:[.font:UIFont.systemFont(ofSize:14,weight:.bold),.foregroundColor:UIColor.label.resolvedColor(with: traits)])
                let size = text.size(); text.draw(at:CGPoint(x:22-size.width/2,y:22-size.height/2))
            }
            if imageCache.count >= 200 { imageCache.removeAll(keepingCapacity: true) }
            imageCache[key] = image
            return image
        }
    }
}

/// Screen-space paths avoid map tile scaling and stay attached to the actual marker head.
struct ScreenOrientation {
    let start: CGPoint
    let end: CGPoint
    let color: UIColor
}
final class OrientationLayer: UIView {
    var arrows: [ScreenOrientation] = [] { didSet { setNeedsDisplay() } }
    init() {
        super.init(frame: .zero)
        backgroundColor = .clear; isOpaque = false; isUserInteractionEnabled = false
        isAccessibilityElement = false; isHidden = true
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setLineCap(.round); context.setLineJoin(.round)
        for arrow in arrows {
            let dx = arrow.end.x-arrow.start.x, dy = arrow.end.y-arrow.start.y
            let magnitude = hypot(dx,dy)
            guard magnitude > 0 else { continue }
            let ux = dx/magnitude, uy = dy/magnitude
            let path = CGMutablePath()
            path.move(to: arrow.start); path.addLine(to: arrow.end)
            let head = CGMutablePath()
            head.move(to: arrow.end)
            head.addLine(to: CGPoint(x: arrow.end.x-ux*8+uy*4.5,y: arrow.end.y-uy*8-ux*4.5))
            head.addLine(to: CGPoint(x: arrow.end.x-ux*8-uy*4.5,y: arrow.end.y-uy*8+ux*4.5))
            head.closeSubpath()
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(5)
            context.addPath(path); context.strokePath()
            context.addPath(head); context.strokePath()
            context.setStrokeColor(arrow.color.resolvedColor(with: traitCollection).cgColor); context.setLineWidth(2.5)
            context.addPath(path); context.strokePath()
            context.setFillColor(arrow.color.resolvedColor(with: traitCollection).cgColor); context.addPath(head); context.fillPath()
        }
    }
}
