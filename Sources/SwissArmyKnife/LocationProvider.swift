//
//  File.swift
//  SwissArmyKnife
//
//  Created by Łukasz Łazarecki on 05/03/2026.
//

import CoreLocation

public final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let queue = SafeDispatchQueue(label: "location.provider.queue")

    private var _latestLocation: CLLocation?
    public var latestLocation: CLLocation? {
        queue.sync { _latestLocation }
    }

    public override init() {
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    public func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    public func stop() {
        manager.stopUpdatingLocation()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }

        //print("location available: \(loc)")
        
        queue.async {
            self._latestLocation = loc
        }
    }
}
