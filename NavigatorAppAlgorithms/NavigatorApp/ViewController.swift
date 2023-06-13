//
//  ViewController.swift
//  NavigatorApp
//
//  Created by Evgenii on 08.06.2023.
//

import UIKit
import MapKit
import CoreLocation
import Layoutless
import AVFoundation

final class ViewController: UIViewController {
    
    var steps: [MKRoute.Step] = []
    var stepCounter = 0
    var route: MKRoute?
    var showMapRoute = false
    var navigationStarted = false
    let locationDistance: Double = 500
    
    var speechSynthesizer = AVSpeechSynthesizer()
    
    lazy var locationManager: CLLocationManager = {
        let locationManager = CLLocationManager()
        DispatchQueue.main.async { [weak self] in
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            self?.handleAuthorizationStatus(locationManager: locationManager, status: locationManager.authorizationStatus)
        }
        return locationManager
    }()
    
    private lazy var directionLabel: UILabel = {
        let label = UILabel()
        label.text = "Where do you want to go?"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    
    private lazy var textField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Enter your destination"
        textField.borderStyle = .roundedRect
        return textField
    }()
    
    private lazy var getDirectionButton: UIButton = {
        let button = UIButton()
        button.setTitle("Get direction", for: .normal)
        button.setTitleColor(.systemBlue, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        button.addTarget(self, action: #selector(getDirectionButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var startsStopButton: UIButton = {
        let button = UIButton()
        button.setTitle("Start Navigation", for: .normal)
        button.setTitleColor(.systemBlue, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        button.addTarget(self, action: #selector(startStopButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.delegate = self
        mapView.showsUserLocation = true
        return mapView
    }()
    
    @objc private func getDirectionButtonTapped() {
        guard let text = textField.text else { return }
        showMapRoute = true
        textField.endEditing(true)
        
        let geoCoder = CLGeocoder()
        geoCoder.geocodeAddressString(text) { placemarks, error in
            if let error = error {
                print(error.localizedDescription)
                return
            }
            
            guard let placemarks = placemarks,
                  let placemark = placemarks.first,
                  let location = placemark.location
            else { return }
            let destinationCoordinate = location.coordinate
            self.mapRoute(destinationCoordinate: destinationCoordinate)
        }
    }
    
    @objc private func startStopButtonTapped() {
        if !navigationStarted {
            showMapRoute = true
            if let location = locationManager.location {
                let center = location.coordinate
                centerViewToUserLocation(center: center)
            }
        } else {
            if let route = route {
                self.mapView.setVisibleMapRect(route.polyline.boundingMapRect,edgePadding: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16), animated: true)
                self.steps.removeAll()
                self.stepCounter = 0
            }
        }
        
        navigationStarted.toggle()
        startsStopButton.setTitle(navigationStarted ? "Stop Navigation" : "Start Navigation", for: .normal)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        locationManager.stopUpdatingLocation()
    }
    
    private func setupViews() {
        view.backgroundColor = .systemBackground
        
        stack(.vertical)(
            directionLabel.insetting(by: 16),
            stack(.horizontal, spacing: 16)(
                textField,
                getDirectionButton
            ).insetting(by: 16),
            startsStopButton.insetting(by: 16),
            mapView
        ).fillingParent(relativeToSafeArea: true).layout(in: view)
    }
    
    private func centerViewToUserLocation(center: CLLocationCoordinate2D) {
        let region = MKCoordinateRegion(center: center, latitudinalMeters: locationDistance, longitudinalMeters: locationDistance)
        mapView.setRegion(region, animated: true)
    }
    
    private func handleAuthorizationStatus(locationManager: CLLocationManager,
                                           status: CLAuthorizationStatus) {
        switch status {
            
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted: break
            //
        case .denied: break
            //
        case .authorizedAlways: break            //
        case .authorizedWhenInUse:
            if let center = locationManager.location?.coordinate {
                centerViewToUserLocation(center: center)
            }
            // to do
        @unknown default:
            break
        }
        
    }
    
    private func mapRoute(destinationCoordinate: CLLocationCoordinate2D) {
        guard let sourceCoordinate = locationManager.location?.coordinate else { return }
        let sourcePlacemark = MKPlacemark(coordinate: sourceCoordinate)
        let destinationPlacemark = MKPlacemark(coordinate: destinationCoordinate)
        
        let sourceItem = MKMapItem(placemark: sourcePlacemark)
        let destinationItem = MKMapItem(placemark: destinationPlacemark)
        
        let routRequest = MKDirections.Request()
        routRequest.source = sourceItem
        routRequest.destination = destinationItem
        routRequest.transportType = .automobile
        
        let directions = MKDirections(request: routRequest)
        directions.calculate { response, error in
            if let error = error {
                print(error.localizedDescription)
                return
            }
            guard let response = response, let route = response.routes.first else { return }
            self.route = route
            self.mapView.addOverlay(route.polyline)
            self.mapView.setVisibleMapRect(route.polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16), animated: true)
            self.getRouteSteps(route: route)
        }
    }
    
    private func getRouteSteps(route: MKRoute) {
        for monitoredRegion in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: monitoredRegion)
        }
        
        let steps = route.steps
        self.steps = steps
        
        for i in 0..<steps.count {
            let step = steps[i]
            print(step.instructions)
            print(step.distance)
            
            let region = CLCircularRegion(center: step.polyline.coordinate, radius: 20, identifier: "\(i)")
            locationManager.startMonitoring(for: region)
        }
        
        stepCounter += 1
        let initialMessage = "In \(steps[stepCounter].distance) meters \(steps[stepCounter].instructions), then in \(steps[stepCounter + 1].distance) meters, \(steps[stepCounter + 1].instructions)"
        directionLabel.text = initialMessage
        let speechUtterance = AVSpeechUtterance(string: initialMessage)
        speechSynthesizer.speak(speechUtterance)
    }
    
}

extension ViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if !showMapRoute {
            if let location = locations.last {
                let center = location.coordinate
                centerViewToUserLocation(center: center)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        handleAuthorizationStatus(locationManager: locationManager, status: status)
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        stepCounter += 1
        if stepCounter < steps.count {
            let message = "In \(steps[stepCounter].distance) meters \(steps[stepCounter].instructions)"
            directionLabel.text = message
            let speechUtterance = AVSpeechUtterance(string: message)
            speechSynthesizer.speak(speechUtterance)
        } else {
            let message = "You have arrived at your destination"
            directionLabel.text = message
            stepCounter = 0
            navigationStarted = false
            for monitoringRegion in locationManager.monitoredRegions {
                locationManager.stopMonitoring(for: monitoringRegion)
            }
        }
    }
}

extension ViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let renderer = MKPolylineRenderer(overlay: overlay)
        renderer.strokeColor = .systemBlue
        return renderer
    }
}
