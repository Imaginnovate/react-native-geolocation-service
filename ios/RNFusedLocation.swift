import Foundation
import CoreLocation

let DEFAULT_ACCURACY: CLLocationAccuracy = kCLLocationAccuracyBest
let DEFAULT_DISTANCE_FILTER: CLLocationDistance = 20

enum LocationError: Int {
  case PERMISSION_DENIED = 1
  case POSITION_UNAVAILABLE
  case TIMEOUT
}

enum AuthorizationStatus: String {
  case disabled, granted, denied, restricted
}

@objc(RNFusedLocation)
class RNFusedLocation: RCTEventEmitter {
  private let locationManager: CLLocationManager = CLLocationManager()
  private var hasListeners: Bool = false
  private var lastLocation: [String: Any] = [:]
  private var observing: Bool = false
  private var timeoutTimer: Timer? = nil
  private var useSignificantChanges: Bool = false
  private var resolveAuthorizationStatus: RCTPromiseResolveBlock? = nil
  private var successCallback: RCTResponseSenderBlock? = nil
  private var errorCallback: RCTResponseSenderBlock? = nil
  public var storeLatitude: Double = 0.0
  public var storeLongitude: Double = 0.0
    
  public var preStoreLatitude: Double = 0.0
  public var preStoreLongitude: Double = 0.0
    var enteredTollsList: [String] = [String]();
    let DISTANCEFILTERVALUE = "distanceFilter";

  override init() {
    super.init()
    locationManager.delegate = self
  }

  deinit {
    if observing {
      useSignificantChanges
        ? locationManager.stopMonitoringSignificantLocationChanges()
        : locationManager.stopUpdatingLocation()

      observing = false
    }

    timeoutTimer?.invalidate()

    locationManager.delegate = nil;
  }

  // MARK: Bridge Method
  @objc func requestAuthorization(
    _ level: String,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) -> Void {
    checkPlistKeys(authorizationLevel: level)

    if !CLLocationManager.locationServicesEnabled() {
      resolve(AuthorizationStatus.disabled.rawValue)
      return
    }

    switch CLLocationManager.authorizationStatus() {
      case .authorizedWhenInUse, .authorizedAlways:
        resolve(AuthorizationStatus.granted.rawValue)
        return
      case .denied:
        resolve(AuthorizationStatus.denied.rawValue)
        return
      case .restricted:
        resolve(AuthorizationStatus.restricted.rawValue)
        return
      default:
        break
    }

    resolveAuthorizationStatus = resolve

    if level == "whenInUse" {
      locationManager.requestWhenInUseAuthorization()
    } else if level == "always" {
      locationManager.requestAlwaysAuthorization()
    }
  }

  // MARK: Bridge Method
  @objc func getCurrentPosition(
    _ options: [String: Any],
    successCallback: @escaping RCTResponseSenderBlock,
    errorCallback: @escaping RCTResponseSenderBlock
  ) -> Void {
    let distanceFilter = options["distanceFilter"] as? Double ?? kCLDistanceFilterNone
    let highAccuracy = options["enableHighAccuracy"] as? Bool ?? false
    let maximumAge = options["maximumAge"] as? Double ?? Double.infinity
    let timeout = options["timeout"] as? Double ?? Double.infinity

    if !lastLocation.isEmpty {
      let elapsedTime = (Date().timeIntervalSince1970 * 1000) - (lastLocation["timestamp"] as! Double)

      if elapsedTime < maximumAge {
        // Return cached location
        successCallback([lastLocation])
        return
      }
    }
    let filterValue = UserDefaults.standard.double(forKey: DISTANCEFILTERVALUE)
    let locManager = CLLocationManager()
    locManager.delegate = self
    locManager.desiredAccuracy = highAccuracy ? kCLLocationAccuracyBest : DEFAULT_ACCURACY
//    locManager.distanceFilter = distanceFilter
    if(filterValue == 0.0) {
        locManager.distanceFilter = 20.0;
        }
        else {
            locManager.distanceFilter = filterValue;
        }
    locManager.requestLocation()

    self.successCallback = successCallback
    self.errorCallback = errorCallback

    if timeout > 0 && timeout != Double.infinity {
      timeoutTimer = Timer.scheduledTimer(
        timeInterval: timeout / 1000.0, // timeInterval is in seconds
        target: self,
        selector: #selector(timerFired),
        userInfo: [
          "errorCallback": errorCallback,
          "manager": locManager
        ],
        repeats: false
      )
    }
  }

  // MARK: Bridge Method
  @objc func startLocationUpdate(_ options: [String: Any]) -> Void {
    let distanceFilter = options["distanceFilter"] as? Double ?? DEFAULT_DISTANCE_FILTER
    let highAccuracy = options["enableHighAccuracy"] as? Bool ?? false
    let significantChanges = options["useSignificantChanges"] as? Bool ?? false

    locationManager.desiredAccuracy = highAccuracy ? kCLLocationAccuracyBest : DEFAULT_ACCURACY
    locationManager.distanceFilter = distanceFilter
    locationManager.allowsBackgroundLocationUpdates = shouldAllowBackgroundUpdate()
    locationManager.pausesLocationUpdatesAutomatically = false

    significantChanges
      ? locationManager.startMonitoringSignificantLocationChanges()
      : locationManager.startUpdatingLocation()

    useSignificantChanges = significantChanges
    observing = true
  }

  // MARK: Bridge Method
  @objc func stopLocationUpdate() -> Void {
    useSignificantChanges
      ? locationManager.stopMonitoringSignificantLocationChanges()
      : locationManager.stopUpdatingLocation()

    observing = false
  }

  @objc func timerFired(timer: Timer) -> Void {
    let data = timer.userInfo as! [String: Any]
    let errorCallback = data["errorCallback"] as! RCTResponseSenderBlock
    let manager = data["manager"] as! CLLocationManager

    manager.stopUpdatingLocation()
    manager.delegate = nil
    errorCallback([generateErrorResponse(code: LocationError.TIMEOUT.rawValue)])
  }

  private func checkPlistKeys(authorizationLevel: String) -> Void {
    #if DEBUG
      let key1 = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription")
      let key2 = Bundle.main.object(forInfoDictionaryKey: "NSLocationAlwaysUsageDescription")
      let key3 = Bundle.main.object(forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription")

      switch authorizationLevel {
        case "whenInUse":
          if key1 == nil {
            RCTMakeAndLogError(
              "NSLocationWhenInUseUsageDescription key must be present in Info.plist",
              nil,
              nil
            )
          }
        case "always":
          if key1 == nil || key2 == nil || key3 == nil {
            RCTMakeAndLogError(
              "NSLocationWhenInUseUsageDescription, NSLocationAlwaysUsageDescription & NSLocationAlwaysAndWhenInUseUsageDescription key must be present in Info.plist",
              nil,
              nil
            )
          }
        default:
          RCTMakeAndLogError("Invalid authorization level provided", nil, nil)
      }
    #endif
  }

  private func shouldAllowBackgroundUpdate() -> Bool {
    let info = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []

    if info.contains("location") {
      return true
    }

    return false
  }

  private func generateErrorResponse(code: Int, message: String = "") -> [String: Any] {
    var msg: String = message

    if msg.isEmpty {
      switch code {
        case LocationError.PERMISSION_DENIED.rawValue:
          msg = "Location permission denied"
        case LocationError.POSITION_UNAVAILABLE.rawValue:
          msg = "Unable to retrieve location due to a network failure"
        case LocationError.TIMEOUT.rawValue:
          msg = "Location request timed out"
        default:
          break
      }
    }

    return [
      "code": code,
      "message": msg
    ]
  }
    /*
     Initiate Geofence and setting geofence to toll plazas
     */
    @objc
    func initoateGeoFencing(_ coordinate: String) {
      let coordinates = coordinate.split(separator: "*");
      print("latitude monitoredRegions.count \(coordinates) \(self.locationManager.monitoredRegions)");
      if(self.locationManager.monitoredRegions.count<20){
        if(coordinates.count>=5){
          let val1 = "\(coordinates[0])".toDouble();
          let val2 = "\(coordinates[1])".toDouble();
          let val3 = coordinates[2];
          let val4 = coordinates[3];
          let radius = "\(coordinates[4])".toDouble();
          var dict:[String:Any] = [String:Any]()
          dict["latitide"] = val1//17.707286700000001//17.7123
          dict["longitude"] =  val2//83.300094700000017//83.3020
          self.createRegion(dict:dict, identifier: String(val3), tollPlazaName: String(val4), geofenseRadius: radius!)
        }
      }
    }
    
    /*
     Creating Geofence to tollplazas
     */
    
    func createRegion(dict:[String:Any], identifier: String, tollPlazaName: String, geofenseRadius: Double)
    {
      print("createRegion \(dict)");
      let identifier = "\(identifier)****\(tollPlazaName)";
      let centerCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2DMake(dict["latitide"] as! Double , dict["longitude"] as! Double)
      let region = CLCircularRegion(center: centerCoordinate, radius:geofenseRadius, identifier:identifier) // provide radius in meter. also provide uniq identifier for your region.
      region.notifyOnEntry = true
      region.notifyOnExit = true
      self.locationManager.startMonitoring(for: region) // to star monitor region
      self.locationManager.startUpdatingLocation()
    }
    
    /*
     It is delegate method of location manager and it moniters to location
     */
    
    
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
      print("The monitored regions are: \(manager.monitoredRegions)")
    }
    
    /*
     It is delegate method of location manager and it called when user enters into geofense region and trigger an event to send one event to reactnative app
     */
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
      
      print("enter the region here...\(region.identifier)")
      if region is CLCircularRegion {
        print("didEnterRegion");
        let identifierArray = region.identifier.components(separatedBy: "****");
        if(identifierArray.count > 1) {
          sendEvent(withName: "nearTOToll", body: [self.storeLatitude, self.storeLongitude, identifierArray[0], identifierArray[1]]);
        }
      }
    }
    
    /*
     It is delegate method of location manager and it called when user exists from geofense region and trigger an event to send one event to reactnative app
     */
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
      print("didExitFromToll")
      let identifierArray = region.identifier.components(separatedBy: "****");
      if(identifierArray.count > 1) {
        sendEvent(withName: "didExitFromToll", body: [self.storeLatitude, self.storeLongitude, identifierArray[0], identifierArray[1]]);
      }
    }
    
    @objc
    func openLocationSettings(_ coordinate: String) {
      guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
        return
      }
      DispatchQueue.main.async {
        if UIApplication.shared.canOpenURL(settingsUrl) {
            if #available(iOS 10.0, *) {
                UIApplication.shared.open(settingsUrl, completionHandler: { (success) in
                    print("Settings opened: \(success)")
                })
            } else {
                // Fallback on earlier versions
            }
        }
      }
    }
    // MARK: Bridge Method
    @objc
    func getLocationStatus(_ callback: RCTResponseSenderBlock) {
        print("getLocationStatus ios")
      var showPopup = false;
      if CLLocationManager.authorizationStatus() == .authorizedAlways {
        self.locationManager.startMonitoringSignificantLocationChanges()
      } else if(CLLocationManager.authorizationStatus() == .authorizedWhenInUse) {
        showPopup = true;
      }
      else if CLLocationManager.authorizationStatus() == .notDetermined {
        self.locationManager.requestAlwaysAuthorization()
        showPopup = true;
      } else if CLLocationManager.authorizationStatus() == .denied {
        print("User denied location permissions.")
        self.locationManager.requestAlwaysAuthorization();
        showPopup = true;
      }
//      self.initializeLocation();
      callback([self.storeLatitude, self.storeLongitude, showPopup])
    }
    
    @objc
    func resetLocationManagerSettings(_ distanceFilter: String) {
      print("distance filter value updated ******* before \(distanceFilter)");
      for region in self.locationManager.monitoredRegions {
          self.locationManager.stopMonitoring(for: region);
      }
      print("remining regions reset geofence radius \(self.locationManager.monitoredRegions)");
      let filterValue = "\(distanceFilter)".toDouble() ?? 20.0;
      UserDefaults.standard.set(filterValue, forKey: DISTANCEFILTERVALUE);
      UserDefaults.standard.synchronize()
      self.locationManager.distanceFilter = filterValue;
    }
    
    func getEnteredPlazaList(enteredGeofences: String) -> [String] {
      self.enteredTollsList.removeAll();
      let geofenceEnterList = enteredGeofences.split(separator: ",");
      for geofenceEnterPlaza in geofenceEnterList {
        self.enteredTollsList.append("\(geofenceEnterPlaza)");
      }
      return self.enteredTollsList;
    }
    
    @objc
    func resetGeofences(_ geofences: String) {
      print("resetGeofences enterslist \(geofences)");
      let enteredList = self.getEnteredPlazaList(enteredGeofences: geofences);
      print("resetGeofences enterslist \(enteredList)");
      for region in self.locationManager.monitoredRegions {
        if(enteredList.contains(region.identifier)) {
          print("\(region.identifier)");
        }else {
          self.locationManager.stopMonitoring(for: region);
        }
      }
      print("after resetGeofences remining regions \(self.locationManager.monitoredRegions)");
    }
}

// MARK: RCTBridgeModule, RCTEventEmitter overrides
extension RNFusedLocation {
  override var methodQueue: DispatchQueue {
    get {
      return DispatchQueue.main
    }
  }

  override static func requiresMainQueueSetup() -> Bool {
    return false
  }

  override func supportedEvents() -> [String]! {
    return ["geolocationDidChange", "geolocationError", "nearTOToll", "callTOTollsList", "locationUpdates", "didExitFromToll", "monitorFailed"]
  }

  override func startObserving() -> Void {
    hasListeners = true
  }

  override func stopObserving() -> Void {
    hasListeners = false
  }
}

extension RNFusedLocation: CLLocationManagerDelegate {
  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    if status == .notDetermined || resolveAuthorizationStatus == nil {
      return
    }

    switch status {
      case .authorizedWhenInUse, .authorizedAlways:
        resolveAuthorizationStatus?(AuthorizationStatus.granted.rawValue)
      case .denied:
        resolveAuthorizationStatus?(AuthorizationStatus.denied.rawValue)
      case .restricted:
        resolveAuthorizationStatus?(AuthorizationStatus.restricted.rawValue)
      default:
        break
    }

    resolveAuthorizationStatus = nil
  }
    
    /*
     Getting distance if distance greater than one km then trigger an event
     and get near tolls list and setting geofence to them.
     */
    
    func isDriverInGreaterThanOneKm(latitude:Double,longitude:Double)->Bool {
      print("latitude \(latitude) longitude \(longitude)");
        print("appDelegate.storeLatitude \(self.preStoreLatitude) appDelegate.storeLongitude \(self.preStoreLongitude)");
      if self.preStoreLatitude == latitude && self.preStoreLongitude == longitude {
        return true
      }
      else if((self.preStoreLatitude == 0.0) && (latitude == 0.0)) {
        return false
      }
      else {
        let currentLocation = CLLocation(latitude: self.preStoreLatitude, longitude: self.preStoreLongitude);
        let previousLocation = CLLocation(latitude: latitude, longitude: longitude);
        let distance = currentLocation.distance(from: previousLocation)
        if distance >= 1000 {
          print("isDriverInGreaterThanOneKm");
          return true
        }
      }
      return false;
    }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location: CLLocation = locations.last else { return }
    let locationData: [String: Any] = [
      "coords": [
        "latitude": location.coordinate.latitude,
        "longitude": location.coordinate.longitude,
        "altitude": location.altitude,
        "accuracy": location.horizontalAccuracy,
        "altitudeAccuracy": location.verticalAccuracy,
        "heading": location.course,
        "speed": location.speed
      ],
      "timestamp": location.timestamp.timeIntervalSince1970 * 1000 // ms
    ]
    
    self.storeLatitude = location.coordinate.latitude;
    self.storeLongitude = location.coordinate.longitude;
    
    if(self.preStoreLatitude == 0.0 || self.preStoreLongitude == 0.0) {
        self.preStoreLatitude = location.coordinate.latitude;
        self.preStoreLongitude = location.coordinate.longitude;
    }
    
    let isDriverInLessThanOneKm = self.isDriverInGreaterThanOneKm(latitude: self.storeLatitude, longitude: self.storeLongitude);
    
    if(isDriverInLessThanOneKm) {
          print("callTOTollsList");
        self.preStoreLatitude = location.coordinate.latitude;
        self.preStoreLongitude = location.coordinate.longitude;
          sendEvent(withName: "callTOTollsList", body: [self.storeLatitude, self.storeLongitude]);
        }
        else {
          sendEvent(withName: "locationUpdates", body: [self.storeLatitude, self.storeLongitude]);
        }
    
    if manager.isEqual(locationManager) && hasListeners && observing {
      sendEvent(withName: "geolocationDidChange", body: locationData)
      return
    }
//    sendEvent(withName: "locationUpdates", body: [self.storeLatitude, self.storeLongitude]);

    guard successCallback != nil else { return }

    lastLocation = locationData
    successCallback!([locationData])

    // Cleanup
    timeoutTimer?.invalidate()
    successCallback = nil
    errorCallback = nil
    manager.delegate = nil
  }
    
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    var errorData: [String: Any] = generateErrorResponse(
      code: LocationError.POSITION_UNAVAILABLE.rawValue,
      message: "Unable to retrieve location"
    )

    if let clErr = error as? CLError {
      switch clErr.code {
        case CLError.denied:
          if !CLLocationManager.locationServicesEnabled() {
            errorData = generateErrorResponse(
              code: LocationError.POSITION_UNAVAILABLE.rawValue,
              message: "Location service is turned off"
            )
          } else {
            errorData = generateErrorResponse(code: LocationError.PERMISSION_DENIED.rawValue)
          }
        case CLError.network:
          errorData = generateErrorResponse(code: LocationError.POSITION_UNAVAILABLE.rawValue)
        default:
          break
      }
    }

    if manager.isEqual(locationManager) && hasListeners && observing {
      sendEvent(withName: "geolocationError", body: errorData)
      return
    }

    guard errorCallback != nil else { return }

    errorCallback!([errorData])

    // Cleanup
    timeoutTimer?.invalidate()
    successCallback = nil
    errorCallback = nil
    manager.delegate = nil
  }
}

extension String {
  func toDouble() -> Double? {
    return NumberFormatter().number(from: self)?.doubleValue
  }
}
