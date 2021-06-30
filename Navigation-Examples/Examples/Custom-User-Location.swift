import UIKit
import MapboxCoreNavigation
import MapboxNavigation
import MapboxDirections
import MapboxMaps

class CustomUserLocationViewController: UIViewController, NavigationMapViewDelegate, NavigationViewControllerDelegate, UIGestureRecognizerDelegate {
    
    var navigationMapView: NavigationMapView! {
        didSet {
            // After the start of active turn-by-turn navigation, the previous `navigationMapView` should be `nil` and removed from super view. It could avoid the location update in the background to disturb the turn-by-turn navigation guidance.
            if let navigationMapView = oldValue {
                navigationMapView.removeFromSuperview()
            }
            
            if navigationMapView != nil {
                setupNavigationMapView()
            }
        }
    }
    
    var navigationRouteOptions: NavigationRouteOptions!
    
    var currentRoute: Route? {
        get {
            return routes?.first
        }
        set {
            guard let selected = newValue else { routes = nil; return }
            guard let routes = routes else { self.routes = [selected]; return }
            self.routes = [selected] + routes.filter { $0 != selected }
        }
    }
    
    var routes: [Route]? {
        didSet {
            guard let routes = routes, let currentRoute = routes.first else {
                navigationMapView?.removeRoutes()
                navigationMapView?.removeRouteDurations()
                navigationMapView?.removeWaypoints()
                waypoints.removeAll()
                return
            }

            navigationMapView.show(routes)
            navigationMapView.showWaypoints(on: currentRoute)
        }
    }
    
    var waypoints: [Waypoint] = []
    
    var startButtonHighlighted: Bool = false {
        didSet {
            startButton.backgroundColor = startButtonHighlighted ? .clear : .blue
        }
    }
    
    private let startButton = UIButton()
    private let clearButton = UIButton()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if navigationMapView == nil {
            navigationMapView = NavigationMapView(frame: view.bounds)
        }
    }
    
    func setupNavigationMapView() {
        navigationMapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        navigationMapView.delegate = self
        navigationMapView.userLocationStyle = .puck2D()
        
        let navigationViewportDataSource = NavigationViewportDataSource(navigationMapView.mapView, viewportDataSourceType: .raw)
        navigationViewportDataSource.options.followingCameraOptions.zoomUpdatesAllowed = false
        navigationViewportDataSource.followingMobileCamera.zoom = 15.0
        navigationMapView.navigationCamera.viewportDataSource = navigationViewportDataSource
        
        view.addSubview(navigationMapView)
        
        setupStartButton()
        setupClearButton()
        setupGestureRecognizers()
    }
    
    func setupClearButton() {
        clearButton.setTitle("Clear", for: .normal)
        clearButton.backgroundColor = .blue
        clearButton.layer.cornerRadius = 5
        clearButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        
        clearButton.addTarget(self, action: #selector(clearMap), for: .touchUpInside)
        view.addSubview(clearButton)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50).isActive = true
        clearButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10).isActive = true
        clearButton.titleLabel?.font = UIFont.systemFont(ofSize: 25)
    }
    
    func setupStartButton() {
        startButton.setTitle("Start", for: .normal)
        startButton.addTarget(self, action: #selector(startButtonChangeColor), for: .touchUpInside)
        startButtonHighlighted = false
        startButton.layer.cornerRadius = 5
        startButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        
        startButton.addTarget(self, action: #selector(performAction), for: .touchUpInside)
        view.addSubview(startButton)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50).isActive = true
        startButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10).isActive = true
        startButton.titleLabel?.font = UIFont.systemFont(ofSize: 25)
    }
    
    func setupGestureRecognizers() {
        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        navigationMapView.gestureRecognizers?.filter({ $0 is UILongPressGestureRecognizer }).forEach(longPressGestureRecognizer.require(toFail:))
        navigationMapView.addGestureRecognizer(longPressGestureRecognizer)
    }
    
    @objc private func startButtonChangeColor() {
        startButtonHighlighted = !startButtonHighlighted
    }
    
    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let gestureLocation = gesture.location(in: navigationMapView)
        let destinationCoordinate = navigationMapView.mapView.mapboxMap.coordinate(for: gestureLocation)
        
        if waypoints.count > 1 {
            waypoints = Array(waypoints.dropFirst())
        }
        
        let waypoint = Waypoint(coordinate: destinationCoordinate, name: "Dropped Pin #\(waypoints.endIndex + 1)")
        waypoint.targetCoordinate = destinationCoordinate
        // Change the coordinate accuracy of `Waypoint` to negative beofre add it to the `waypoints`. Thus the route requested on the `waypoints` is considered viable.
        waypoint.coordinateAccuracy = -1
        waypoints.append(waypoint)

        requestRoute()
    }
    
    func requestRoute() {
        guard waypoints.count > 0 else { return }
        guard let currentCoordinate = navigationMapView.mapView.location.latestLocation?.coordinate else {
            print("User location is not valid. Make sure to enable Location Services.")
            return
        }

        let userWaypoint = Waypoint(coordinate: currentCoordinate)
        // Change the coordinate accuracy of `Waypoint` to negative beofre add it to the `waypoints`. Thus the route requested on the `waypoints` is considered viable.
        userWaypoint.coordinateAccuracy = -1
        waypoints.insert(userWaypoint, at: 0)
        let navigationRouteOptions = NavigationRouteOptions(waypoints: waypoints)
        
        Directions.shared.calculate(navigationRouteOptions) { [weak self] (_, result) in
            switch result {
            case .failure(let error):
                print(error.localizedDescription)
                self?.waypoints.removeLast()
            case .success(let response):
                guard let routes = response.routes else { return }
                self?.navigationRouteOptions = navigationRouteOptions
                self?.routes = routes
                self?.navigationMapView.show(routes)
                if let currentRoute = self?.currentRoute {
                    self?.navigationMapView.showWaypoints(on: currentRoute)
                }
            }
        }
    }
    
    @objc func clearMap(_ sender: Any) {
        routes = nil
    }
    
    @objc func performAction(_ sender: Any) {
        // Set Up the alert controller to switch between different userLocationStyle.
        let alertController = UIAlertController(title: "Choose UserLocationStyle",
                                                message: "Select the user location style",
                                                preferredStyle: .actionSheet)
        
        typealias ActionHandler = (UIAlertAction) -> Void
        
        let courseView: ActionHandler = { _ in self.setupCourseView() }
        let puck2D: ActionHandler = { _ in self.setupPuck2D() }
        let puck3D: ActionHandler = { _ in self.setupPuck3D() }
        let cancel: ActionHandler = { _ in self.startButtonHighlighted = false }
        
        let actionPayloads: [(String, UIAlertAction.Style, ActionHandler?)] = [
            ("Default Course View", .default, courseView),
            ("2D Arrow Puck", .default, puck2D),
            ("3D Car Puck", .default, puck3D),
            ("Cancel", .cancel, cancel)
        ]
        
        actionPayloads
            .map { payload in UIAlertAction(title: payload.0, style: payload.1, handler: payload.2) }
            .forEach(alertController.addAction(_:))
        
        if let popoverController = alertController.popoverPresentationController {
            popoverController.sourceView = self.startButton
            popoverController.sourceRect = self.startButton.bounds
        }
        
        present(alertController, animated: true, completion: nil)
    }
    
    func setupCourseView() {
        // Given configuration to the `UserLocationStyle.courseView` through the customizing of `UserPuckCourseView`. Both `UserPuckCourseView` and `UserHaloView` are subclassable.
        // By default `NavigationMapView.userLocationStyle` property is set to `UserLocationStyle.courseView(_:)`.
        presentNavigationViewController()
    }
    
    func setupPuck2D() {
        // It's optional to set up `Puck2DConfiguration` to the `UserLocationStyle.puck2D`. Otherwise the defualt configutaion for the `UserLocationStyle.puck2D` is `Puck2DConfiguration()`.
        var puck2DConfiguration = Puck2DConfiguration()
        if #available(iOS 13.0, *) {
            puck2DConfiguration.topImage = UIImage(systemName: "arrow.up")
            puck2DConfiguration.scale = .constant(2.0)
        }
        
        let userLocationStyle = UserLocationStyle.puck2D(configuration: puck2DConfiguration)
        presentNavigationViewController(userLocationStyle)
    }
    
    func setupPuck3D() {
        // It's required to provide a `Puck3DConfiguration` to the `UserLocationStyle.puck3D`, a `gltf` 3D asset will be used as the `Model` source.
        // The model source is from NASA's curiosity(clean) in https://github.com/nasa/NASA-3D-Resources/blob/master/3D%20Models/Curiosity%20(Clean)/MSL_clean.blend
        let uri = Bundle.main.url(forResource: "MSL_clean",
                                  withExtension: "gltf")
        // Instantiating the model. The position is the coordinates of the model in `[longitude, latitude]` format.
        let myModel = Model(uri: uri,
                            position: [-122.396152, 37.79129],
                            orientation: [0, 0, 0])
        // Setting an expression to scale the model based on camera zoom
        let scalingExpression = Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            0
            Exp(.literal) {
                [256000.0, 256000.0, 256000.0]
            }
            4
            Exp(.literal) {
                [40000.0, 40000.0, 40000.0]
            }
            8
            Exp(.literal) {
                [2000.0, 2000.0, 2000.0]
            }
            12
            Exp(.literal) {
                [100.0, 100.0, 100.0]
            }
            16
            Exp(.literal) {
                [10.0, 10.0, 10.0]
            }
            20
            Exp(.literal) {
                [3.0, 3.0, 3.0]
            }
        }
        
        let puck3DConfiguration = Puck3DConfiguration(model: myModel, modelScale: .expression(scalingExpression))
        let userLocationStyle = UserLocationStyle.puck3D(configuration: puck3DConfiguration)
        presentNavigationViewController(userLocationStyle)
    }
    
    func presentNavigationViewController(_ userLocationStyle: UserLocationStyle? = nil) {
        guard let route = currentRoute, let navigationRouteOptions = navigationRouteOptions else { return }

        let navigationService = MapboxNavigationService(route: route,
                                                        routeIndex: 0,
                                                        routeOptions: navigationRouteOptions,
                                                        simulating: simulationIsEnabled ? .always : .onPoorGPS)
        let navigationOptions = NavigationOptions(navigationService: navigationService)
        let navigationViewController = NavigationViewController(for: route,
                                                                routeIndex: 0,
                                                                routeOptions: navigationRouteOptions,
                                                                navigationOptions: navigationOptions)
        navigationViewController.routeLineTracksTraversal = true
        navigationViewController.delegate = self
        navigationViewController.modalPresentationStyle = .fullScreen
        
        // If not customizing the `NavigationMapView.userLocationStyle`, it defaults as the `UserLocationStyle.courseView(_:)`.
        if let userLocationStyle = userLocationStyle {
            navigationViewController.navigationMapView?.userLocationStyle = userLocationStyle
        }

        navigationViewController.navigationMapView?.mapView.mapboxMap.style.uri = navigationMapView.mapView?.mapboxMap.style.uri
        
        present(navigationViewController, animated: true) {
            // When start navigation, the previous `navigationMapView` should be `nil` and removed from super view. The niled out `navigationMapView` could avoid the location provider sending location update in the background, which will disturb the turn-by-turn navigation guidance.
            self.navigationMapView = nil
        }
    }
    
    func navigationViewControllerDidDismiss(_ navigationViewController: NavigationViewController, byCanceling canceled: Bool) {
        routes = nil
        dismiss(animated: true, completion: nil)
        if navigationMapView == nil {
            navigationMapView = NavigationMapView(frame: view.bounds)
        }
    }
}
