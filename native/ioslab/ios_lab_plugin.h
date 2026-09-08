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
	void set_background_location_enabled(bool enabled);
	bool is_background_location_enabled() const;

	void start_ble_scan();
	void stop_ble_scan();
	int get_ble_state() const;

	bool is_arkit_supported() const;
	bool is_lidar_supported() const;
	bool is_nfc_available() const;

	float get_battery_level() const;
	int get_battery_state() const;

	void emit_location_authorization(int status);
	void emit_location(double latitude, double longitude, double accuracy, double altitude, double speed);
	void emit_ble_state(int state);
	void emit_ble_device(const String &name, const String &uuid, int rssi);
};

void ios_lab_init();
void ios_lab_deinit();
