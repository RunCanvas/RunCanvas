//
//  LocationManager.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI
import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    private let locationManager = CLLocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var totalDistance: Double = 0
    
    private var lastLocation: CLLocation?
    
    override init() {
        super.init()
        
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
    }
    
    // 위치 권한 요청
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    // GPS 위치 추적 시작
    func startUpdatingLocation() {
        lastLocation = nil
        locationManager.startUpdatingLocation()
    }
    
    // GPS 위치 추적 중지
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
    
    // 새로운 위치를 받았을 때 실행
    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let newLocation = locations.last else {
            return
        }
        
        // 정확도가 좋지 않은 위치는 무시
        guard newLocation.horizontalAccuracy >= 0,
              newLocation.horizontalAccuracy <= 20 else {
            return
        }
        
        // 현재 위치 저장
        currentLocation = newLocation
        
        // 첫 번째 위치라면 기준점만 저장
        guard let lastLocation = lastLocation else {
            self.lastLocation = newLocation
            return
        }
        
        let distance = newLocation.distance(from: lastLocation)
        
        // 너무 작은 GPS 흔들림은 이동으로 계산하지 않음
        if distance >= 5 {
            totalDistance += distance
            self.lastLocation = newLocation
        }
    }
}
