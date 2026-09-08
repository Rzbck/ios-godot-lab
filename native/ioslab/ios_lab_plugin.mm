#import <ARKit/ARKit.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreNFC/CoreNFC.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include "core/config/engine.h"
#include "core/object/class_db.h"
#include "ios_lab_plugin.h"

@class IOSLabDelegate;
static IOSLabDelegate *ios_lab_delegate = nil;
static IOSLabPlugin *ios_lab_plugin_instance = nullptr;


@interface IOSLabDelegate : NSObject <CLLocationManagerDelegate, CBCentralManagerDelegate>
@property(nonatomic, strong) CLLocationManager *locationManager;
@property(nonatomic, strong) CBCentralManager *centralManager;
@property(nonatomic, assign) IOSLabPlugin *owner;
@property(nonatomic, assign) BOOL backgroundLocationEnabled;
- (instancetype)initWithOwner:(IOSLabPlugin *)owner;
- (void)ensureCentralManager;
@end


@implementation IOSLabDelegate

- (instancetype)initWithOwner:(IOSLabPlugin *)owner {
	self = [super init];
	if (self) {
		_owner = owner;
		_backgroundLocationEnabled = NO;
		_locationManager = [[CLLocationManager alloc] init];
		_locationManager.delegate = self;
		_locationManager.desiredAccuracy = kCLLocationAccuracyBest;
		_locationManager.distanceFilter = kCLDistanceFilterNone;
		_locationManager.activityType = CLActivityTypeOther;
		_locationManager.pausesLocationUpdatesAutomatically = YES;
	}
	return self;
}

- (void)ensureCentralManager {
	if (_centralManager == nil) {
		_centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
	}
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
	if (_owner != nullptr) {
		_owner->emit_location_authorization((int)manager.authorizationStatus);
	}
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
	if (_owner != nullptr) {
		_owner->emit_location_authorization((int)status);
	}
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
	CLLocation *location = locations.lastObject;
	if (location == nil || _owner == nullptr) {
		return;
	}

	_owner->emit_location(
		location.coordinate.latitude,
		location.coordinate.longitude,
		location.horizontalAccuracy,
		location.altitude,
		location.speed
	);
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
	NSLog(@"IOSLab CoreLocation error: %@", error);
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
	if (_owner != nullptr) {
		_owner->emit_ble_state((int)central.state);
	}
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary<NSString *, id> *)advertisementData
                  RSSI:(NSNumber *)RSSI {
	if (_owner == nullptr) {
		return;
	}

	NSString *name = peripheral.name;
	if (name == nil || name.length == 0) {
		name = advertisementData[CBAdvertisementDataLocalNameKey];
	}
	if (name == nil) {
		name = @"";
	}

	NSString *uuid = peripheral.identifier.UUIDString ?: @"";
	_owner->emit_ble_device(
		String::utf8(name.UTF8String),
		String::utf8(uuid.UTF8String),
		RSSI.intValue
	);
}

@end


IOSLabPlugin *IOSLabPlugin::singleton = nullptr;


void IOSLabPlugin::_bind_methods() {
	ClassDB::bind_method(D_METHOD("request_location"), &IOSLabPlugin::request_location);
	ClassDB::bind_method(D_METHOD("start_location"), &IOSLabPlugin::start_location);
	ClassDB::bind_method(D_METHOD("stop_location"), &IOSLabPlugin::stop_location);
	ClassDB::bind_method(D_METHOD("set_background_location_enabled", "enabled"), &IOSLabPlugin::set_background_location_enabled);
	ClassDB::bind_method(D_METHOD("is_background_location_enabled"), &IOSLabPlugin::is_background_location_enabled);
	ClassDB::bind_method(D_METHOD("start_ble_scan"), &IOSLabPlugin::start_ble_scan);
	ClassDB::bind_method(D_METHOD("stop_ble_scan"), &IOSLabPlugin::stop_ble_scan);
	ClassDB::bind_method(D_METHOD("get_ble_state"), &IOSLabPlugin::get_ble_state);
	ClassDB::bind_method(D_METHOD("is_arkit_supported"), &IOSLabPlugin::is_arkit_supported);
	ClassDB::bind_method(D_METHOD("is_lidar_supported"), &IOSLabPlugin::is_lidar_supported);
	ClassDB::bind_method(D_METHOD("is_nfc_available"), &IOSLabPlugin::is_nfc_available);
	ClassDB::bind_method(D_METHOD("get_battery_level"), &IOSLabPlugin::get_battery_level);
	ClassDB::bind_method(D_METHOD("get_battery_state"), &IOSLabPlugin::get_battery_state);

	ADD_SIGNAL(MethodInfo(
		"location_authorization_changed",
		PropertyInfo(Variant::INT, "status")
	));
	ADD_SIGNAL(MethodInfo(
		"location_updated",
		PropertyInfo(Variant::FLOAT, "latitude"),
		PropertyInfo(Variant::FLOAT, "longitude"),
		PropertyInfo(Variant::FLOAT, "accuracy"),
		PropertyInfo(Variant::FLOAT, "altitude"),
		PropertyInfo(Variant::FLOAT, "speed")
	));
	ADD_SIGNAL(MethodInfo(
		"ble_state_changed",
		PropertyInfo(Variant::INT, "state")
	));
	ADD_SIGNAL(MethodInfo(
		"ble_device_found",
		PropertyInfo(Variant::STRING, "name"),
		PropertyInfo(Variant::STRING, "uuid"),
		PropertyInfo(Variant::INT, "rssi")
	));
}


IOSLabPlugin *IOSLabPlugin::get_singleton() {
	return singleton;
}


IOSLabPlugin::IOSLabPlugin() {
	singleton = this;
	ios_lab_delegate = [[IOSLabDelegate alloc] initWithOwner:this];
	[UIDevice currentDevice].batteryMonitoringEnabled = YES;
}


IOSLabPlugin::~IOSLabPlugin() {
	if (ios_lab_delegate != nil) {
		[ios_lab_delegate.locationManager stopUpdatingLocation];
		ios_lab_delegate.locationManager.allowsBackgroundLocationUpdates = NO;
		ios_lab_delegate.locationManager.showsBackgroundLocationIndicator = NO;
		[ios_lab_delegate.centralManager stopScan];
		ios_lab_delegate.locationManager.delegate = nil;
		ios_lab_delegate.centralManager.delegate = nil;
		ios_lab_delegate.owner = nullptr;
		ios_lab_delegate = nil;
	}
	[UIDevice currentDevice].batteryMonitoringEnabled = NO;
	singleton = nullptr;
}


void IOSLabPlugin::request_location() {
	if (ios_lab_delegate == nil) {
		return;
	}
	[ios_lab_delegate.locationManager requestWhenInUseAuthorization];
	emit_location_authorization((int)ios_lab_delegate.locationManager.authorizationStatus);
}


void IOSLabPlugin::start_location() {
	if (ios_lab_delegate != nil) {
		[ios_lab_delegate.locationManager startUpdatingLocation];
	}
}


void IOSLabPlugin::stop_location() {
	if (ios_lab_delegate != nil) {
		[ios_lab_delegate.locationManager stopUpdatingLocation];
	}
}


void IOSLabPlugin::set_background_location_enabled(bool enabled) {
	if (ios_lab_delegate == nil) {
		return;
	}

	CLLocationManager *manager = ios_lab_delegate.locationManager;
	ios_lab_delegate.backgroundLocationEnabled = enabled ? YES : NO;
	manager.activityType = enabled ? CLActivityTypeFitness : CLActivityTypeOther;
	manager.pausesLocationUpdatesAutomatically = enabled ? NO : YES;
	manager.distanceFilter = enabled ? 2.0 : kCLDistanceFilterNone;
	manager.allowsBackgroundLocationUpdates = enabled ? YES : NO;
	manager.showsBackgroundLocationIndicator = enabled ? YES : NO;
}


bool IOSLabPlugin::is_background_location_enabled() const {
	return ios_lab_delegate != nil && ios_lab_delegate.backgroundLocationEnabled == YES;
}


void IOSLabPlugin::start_ble_scan() {
	if (ios_lab_delegate == nil) {
		return;
	}

	[ios_lab_delegate ensureCentralManager];
	if (ios_lab_delegate.centralManager.state == CBManagerStatePoweredOn) {
		[ios_lab_delegate.centralManager scanForPeripheralsWithServices:nil
			options:@{ CBCentralManagerScanOptionAllowDuplicatesKey : @NO }];
	}
}


void IOSLabPlugin::stop_ble_scan() {
	if (ios_lab_delegate != nil && ios_lab_delegate.centralManager != nil) {
		[ios_lab_delegate.centralManager stopScan];
	}
}


int IOSLabPlugin::get_ble_state() const {
	if (ios_lab_delegate == nil) {
		return -1;
	}
	[ios_lab_delegate ensureCentralManager];
	return (int)ios_lab_delegate.centralManager.state;
}


bool IOSLabPlugin::is_arkit_supported() const {
	return [ARWorldTrackingConfiguration isSupported];
}


bool IOSLabPlugin::is_lidar_supported() const {
	if (@available(iOS 13.4, *)) {
		return [ARWorldTrackingConfiguration supportsSceneReconstruction:ARSceneReconstructionMesh];
	}
	return false;
}


bool IOSLabPlugin::is_nfc_available() const {
	if (@available(iOS 11.0, *)) {
		return [NFCNDEFReaderSession readingAvailable];
	}
	return false;
}


float IOSLabPlugin::get_battery_level() const {
	UIDevice *device = [UIDevice currentDevice];
	device.batteryMonitoringEnabled = YES;
	return device.batteryLevel;
}


int IOSLabPlugin::get_battery_state() const {
	UIDevice *device = [UIDevice currentDevice];
	device.batteryMonitoringEnabled = YES;
	return (int)device.batteryState;
}


void IOSLabPlugin::emit_location_authorization(int status) {
	emit_signal("location_authorization_changed", status);
}


void IOSLabPlugin::emit_location(double latitude, double longitude, double accuracy, double altitude, double speed) {
	emit_signal("location_updated", latitude, longitude, accuracy, altitude, speed);
}


void IOSLabPlugin::emit_ble_state(int state) {
	emit_signal("ble_state_changed", state);
}


void IOSLabPlugin::emit_ble_device(const String &name, const String &uuid, int rssi) {
	emit_signal("ble_device_found", name, uuid, rssi);
}


void ios_lab_init() {
	if (ios_lab_plugin_instance != nullptr) {
		return;
	}
	ios_lab_plugin_instance = memnew(IOSLabPlugin);
	Engine::get_singleton()->add_singleton(Engine::Singleton("IOSLab", ios_lab_plugin_instance));
}


void ios_lab_deinit() {
	if (ios_lab_plugin_instance != nullptr) {
		memdelete(ios_lab_plugin_instance);
		ios_lab_plugin_instance = nullptr;
	}
}
