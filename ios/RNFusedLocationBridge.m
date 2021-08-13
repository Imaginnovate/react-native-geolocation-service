#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface RCT_EXTERN_MODULE(RNFusedLocation, RCTEventEmitter)

RCT_EXTERN_METHOD(
  requestAuthorization:(NSString *)level
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject
)

RCT_EXTERN_METHOD(
  getCurrentPosition:(NSDictionary *)options
     successCallback:(RCTResponseSenderBlock)successCallback
       errorCallback:(RCTResponseSenderBlock)errorCallback
)

_RCT_EXTERN_REMAP_METHOD(
  startObserving,
  startLocationUpdate:(NSDictionary *)options,
  false
)

_RCT_EXTERN_REMAP_METHOD(stopObserving, stopLocationUpdate, false)

RCT_EXTERN_METHOD(getLocationStatus: (RCTResponseSenderBlock)callback)
RCT_EXTERN_METHOD(initoateGeoFencing: (NSString *)coordinate)
RCT_EXTERN_METHOD(resetGeofences: (NSString *)geofences)
RCT_EXTERN_METHOD(openLocationSettings: (NSString *)coordinate)
RCT_EXTERN_METHOD(resetLocationManagerSettings: (NSString *)distanceFilter)

@end

