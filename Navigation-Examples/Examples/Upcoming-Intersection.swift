/*
 This code example is part of the Mapbox Navigation SDK for iOS demo app,
 which you can build and run: https://github.com/mapbox/mapbox-navigation-ios-examples
 To learn more about each example in this app, including descriptions and links
 to documentation, see our docs: https://docs.mapbox.com/ios/navigation/examples/electronic-horizon
 */

import UIKit
import MapboxNavigation
import MapboxCoreNavigation
import MapboxMaps
import Turf

class ElectronicHorizonEventsViewController: UIViewController {

    private lazy var navigationMapView = NavigationMapView(frame: view.bounds)

    private let upcomingIntersectionLabel = UILabel()
    private let passiveLocationManager = PassiveLocationManager()
    private lazy var passiveLocationProvider = PassiveLocationProvider(locationManager: passiveLocationManager)
    private let routeLineColor: UIColor = .green.withAlphaComponent(0.9)
    private let traversedRouteColor: UIColor = .clear
    private var totalDistance: CLLocationDistance = 0.0

    var roadObjectStore: RoadObjectStore {
        return passiveLocationManager.roadObjectStore
    }

    let myRoadObjectPolygon = Polygon([[
        LocationCoordinate2D(latitude: 35.461721760959406, longitude: 139.87926747747304),
        LocationCoordinate2D(latitude: 35.46085662774896,  longitude: 139.87840917058827),
        LocationCoordinate2D(latitude: 35.46479936316225,  longitude: 139.87277450781156),
        LocationCoordinate2D(latitude: 35.46557707147994,  longitude: 139.8735577128439),
        LocationCoordinate2D(latitude: 35.461721760959406, longitude: 139.87926747747304),
    ]])

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupNavigationMapView()
        setupUpcomingIntersectionLabel()
        setupMyRoadObject()
        setupElectronicHorizonUpdates()
    }

    func setupNavigationMapView() {
        navigationMapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        navigationMapView.mapView.location.overrideLocationProvider(with: passiveLocationProvider)
        navigationMapView.userLocationStyle = .puck2D()
        navigationMapView.mapView.mapboxMap.onNext(event: .styleLoaded, handler: { [weak self] _ in
            self?.setupMostProbablePathStyle()
            self?.setupMyRoadObjectStyle()
        })
        
        view.addSubview(navigationMapView)
    }

    func setupMyRoadObject() {
        passiveLocationManager.roadObjectMatcher.delegate = self
        passiveLocationManager.roadObjectMatcher.match(polygon: myRoadObjectPolygon, identifier: "myRoadObjectIdentifier")
    }

    func setupElectronicHorizonUpdates() {
        // Customize the `ElectronicHorizonOptions` for `PassiveLocationManager` to start Electronic Horizon updates.
        let options = ElectronicHorizonOptions(length: 500, expansionLevel: 1, branchLength: 500, minTimeDeltaBetweenUpdates: 3)
        passiveLocationManager.startUpdatingElectronicHorizon(with: options)
        subscribeToElectronicHorizonUpdates()
    }

    private func setupUpcomingIntersectionLabel() {
        upcomingIntersectionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(upcomingIntersectionLabel)

        let safeAreaWidthAnchor = view.safeAreaLayoutGuide.widthAnchor
        NSLayoutConstraint.activate([
            upcomingIntersectionLabel.widthAnchor.constraint(lessThanOrEqualTo: safeAreaWidthAnchor, multiplier: 0.9),
            upcomingIntersectionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            upcomingIntersectionLabel.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor)
        ])
        upcomingIntersectionLabel.backgroundColor = #colorLiteral(red: 0.9568627477, green: 0.6588235497, blue: 0.5450980663, alpha: 1)
        upcomingIntersectionLabel.layer.cornerRadius = 5
        upcomingIntersectionLabel.numberOfLines = 0
    }

    private func subscribeToElectronicHorizonUpdates() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didUpdateElectronicHorizonPosition),
                                               name: .electronicHorizonDidUpdatePosition,
                                               object: nil)
    }

    @objc private func didUpdateElectronicHorizonPosition(_ notification: Notification) {
        let horizonTreeKey = RoadGraph.NotificationUserInfoKey.treeKey
        guard let horizonTree = notification.userInfo?[horizonTreeKey] as? RoadGraph.Edge,
              let position = notification.userInfo?[RoadGraph.NotificationUserInfoKey.positionKey] as? RoadGraph.Position,
              let updatesMostProbablePath = notification.userInfo?[RoadGraph.NotificationUserInfoKey.updatesMostProbablePathKey] as? Bool else {
            return
        }

        let currentStreetName = streetName(for: horizonTree)
        let upcomingCrossStreet = nearestCrossStreetName(from: horizonTree)
        updateLabel(currentStreetName: currentStreetName, predictedCrossStreet: upcomingCrossStreet)

        // Update the most probable path when the position update indicates a new most probable path (MPP).
        if updatesMostProbablePath {
            let mostProbablePath = routeLine(from: horizonTree, roadGraph: passiveLocationManager.roadGraph)
            updateMostProbablePath(with: mostProbablePath)
        }
        
        // Update the most probable path layer when the position update indicates
        // a change of the fraction of the point traveled distance to the current edge’s length.
        updateMostProbablePathLayer(fractionFromStart: position.fractionFromStart,
                                    roadGraph: passiveLocationManager.roadGraph,
                                    currentEdge: horizonTree.identifier)

        printUpcomingRoadObjects(horizonTree: horizonTree)
    }

    func printUpcomingRoadObjects(horizonTree: RoadGraph.Edge) {
        let allEdges = extractAllEdges(from: horizonTree)
        let allEdgeIdentifiers = allEdges.map { $0.identifier }
        let roadObjectIdentifiers = roadObjectStore.roadObjectIdentifiers(edgeIdentifiers: allEdgeIdentifiers)
        let roadObjects = roadObjectIdentifiers.compactMap { roadObjectStore.roadObject(identifier: $0) }

        print("=============== upcoming road objects ===============")
        roadObjects.forEach { roadObject in
            print("kind: \(roadObject.kind) isUserDefined: \(roadObject.isUserDefined) id: \(roadObject.identifier)")
        }
    }

    func extractAllEdges(from edge: RoadGraph.Edge) -> [RoadGraph.Edge] {
        return [edge] + edge.outletEdges.flatMap { extractAllEdges(from: $0) }
    }

    private func streetName(for edge: RoadGraph.Edge) -> String? {
        let edgeMetadata = passiveLocationManager.roadGraph.edgeMetadata(edgeIdentifier: edge.identifier)
        return edgeMetadata?.names.first.map { roadName in
            switch roadName {
            case .name(let name):
                return name
            case .code(let code):
                return "\(code)"
            }
        }
    }

    private func nearestCrossStreetName(from edge: RoadGraph.Edge) -> String? {
        let initialStreetName = streetName(for: edge)
        var currentEdge: RoadGraph.Edge? = edge
        while let nextEdge = currentEdge?.outletEdges.max(by: { $0.probability < $1.probability }) {
            if let nextStreetName = streetName(for: nextEdge), nextStreetName != initialStreetName {
                return nextStreetName
            }
            currentEdge = nextEdge
        }
        return nil
    }

    private func updateLabel(currentStreetName: String?, predictedCrossStreet: String?) {
        var statusString = ""
        if let currentStreetName = currentStreetName {
            statusString = "Currently on:\n\(currentStreetName)"
            if let predictedCrossStreet = predictedCrossStreet {
                statusString += "\nUpcoming intersection with:\n\(predictedCrossStreet)"
            } else {
                statusString += "\nNo upcoming intersections"
            }
        }

        DispatchQueue.main.async {
            self.upcomingIntersectionLabel.text = statusString
            self.upcomingIntersectionLabel.sizeToFit()
        }
    }

    // MARK: - Drawing the most probable path
    private let sourceIdentifier = "mpp-source"
    private let layerIdentifier = "mpp-layer"

    private func routeLine(from edge: RoadGraph.Edge, roadGraph: RoadGraph) -> [LocationCoordinate2D] {
        var coordinates = [LocationCoordinate2D]()
        var edge: RoadGraph.Edge? = edge
        totalDistance = 0.0
        
        // Update the route line shape and total distance of the most probable path.
        while let currentEdge = edge {
            if let shape = roadGraph.edgeShape(edgeIdentifier: currentEdge.identifier) {
                coordinates.append(contentsOf: shape.coordinates.dropFirst(coordinates.isEmpty ? 0 : 1))
            }
            if let distance = roadGraph.edgeMetadata(edgeIdentifier: currentEdge.identifier)?.length {
                totalDistance += distance
            }
            edge = currentEdge.outletEdges.max(by: { $0.probability < $1.probability })
        }
        return coordinates
    }

    private func updateMostProbablePath(with mostProbablePath: [CLLocationCoordinate2D]) {
        let feature = Feature(geometry: .lineString(LineString(mostProbablePath)))
        try? navigationMapView.mapView.mapboxMap.style.updateGeoJSONSource(withId: sourceIdentifier,
                                                                           geoJSON: .feature(feature))
    }
    
    private func updateMostProbablePathLayer(fractionFromStart: Double,
                                             roadGraph: RoadGraph,
                                             currentEdge: RoadGraph.Edge.Identifier) {
        // Based on the length of current edge and the total distance of the most probable path (MPP),
        // calculate the fraction of the point traveled distance to the whole most probable path (MPP).
        if totalDistance > 0.0,
           let currentLength = roadGraph.edgeMetadata(edgeIdentifier: currentEdge)?.length {
            let fraction = fractionFromStart * currentLength / totalDistance
            updateMostProbablePathLayerFraction(fraction)
        }
    }
    
    private func setupMostProbablePathStyle() {
        var source = GeoJSONSource()
        source.data = .geometry(Geometry.lineString(LineString([])))
        source.lineMetrics = true
        try? navigationMapView.mapView.mapboxMap.style.addSource(source, id: sourceIdentifier)
        
        var layer = LineLayer(id: layerIdentifier)
        layer.source = sourceIdentifier
        layer.lineWidth = .expression(
            Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                RouteLineWidthByZoomLevel.mapValues { $0 * 0.5 }
            }
        )
        layer.lineColor = .constant(.init(routeLineColor))
        layer.lineCap = .constant(.round)
        layer.lineJoin = .constant(.miter)
        layer.minZoom = 9
        try? navigationMapView.mapView.mapboxMap.style.addLayer(layer)
    }

    private func setupMyRoadObjectStyle() {
        let sourceIdentifier = "myRoadObjectSource"
        var source = GeoJSONSource()
        source.data = .geometry(Geometry.polygon(myRoadObjectPolygon))
        try? navigationMapView.mapView.mapboxMap.style.addSource(source, id: sourceIdentifier)

        var layer = FillLayer(id: "myRoadObjectLayer")
        layer.source = sourceIdentifier
        layer.fillColor = .constant(.init(.red))
        layer.fillOpacity = .constant(0.5)
        try? navigationMapView.mapView.mapboxMap.style.addLayer(layer)
    }

    // Update the line gradient property of the most probable path line layer,
    // so the part of the most probable path that has been traversed will be rendered with full transparency.
    private func updateMostProbablePathLayerFraction(_ fraction: Double) {
        let nextDown = max(fraction.nextDown, 0.0)
        let exp = Exp(.step) {
            Exp(.lineProgress)
            traversedRouteColor
            nextDown
            traversedRouteColor
            fraction
            routeLineColor
        }
        
        if let data = try? JSONEncoder().encode(exp.self),
           let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
            try? navigationMapView.mapView.mapboxMap.style.setLayerProperty(for: layerIdentifier,
                                                                            property: "line-gradient",
                                                                            value: jsonObject)
        }
    }
}

extension ElectronicHorizonEventsViewController: RoadObjectMatcherDelegate {
    func roadObjectMatcher(_ matcher: MapboxCoreNavigation.RoadObjectMatcher, didMatch roadObject: MapboxCoreNavigation.RoadObject) {
        print(#function)
        roadObjectStore.addUserDefinedRoadObject(roadObject)
    }

    func roadObjectMatcher(_ matcher: MapboxCoreNavigation.RoadObjectMatcher, didFailToMatchWith error: MapboxCoreNavigation.RoadObjectMatcherError) {
        print(#function)
    }

    func roadObjectMatcher(_ matcher: MapboxCoreNavigation.RoadObjectMatcher, didCancelMatchingFor id: String) {
        print(#function)
    }
}
