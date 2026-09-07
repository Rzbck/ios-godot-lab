#pragma once

#include "core/object/class_db.h"
#include "core/object/object.h"

class IOSLabPlugin : public Object {
	GDCLASS(IOSLabPlugin, Object);

	static IOSLabPlugin *singleton;

protected:
	static void _bind_methods();

public:
	static IOSLabPlugin *get_singleton();

	IOSLabPlugin();
	~IOSLabPlugin();

	void request_location();
	void start_location();
	void stop_location();

	void start_ble_scan();
	void stop_ble_scan();
	int get_ble_state() const;

	bool is_arkit_supported() const;
	bool is_lidar_supported() const;
	bool is_nfc_available() const;

	void emit_location_authorization(int status);
	void emit_location(double latitude, double longitude, double accuracy, double altitude, double speed);
	void emit_ble_state(int state);
	void emit_ble_device(const String &name, const String &uuid, int rssi);
};

extern "C" void ios_lab_init();
extern "C" void ios_lab_deinit();
