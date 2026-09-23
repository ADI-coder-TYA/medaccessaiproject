class EmergencyFacility {
  final String id;
  final String name;
  final String type;
  final String address;
  final String phone;
  final double latitude;
  final double longitude;
  final String openStatus;
  final bool isOpen24Hours;
  final List<String> capabilities;
  final double distanceKm;
  final int travelTimeMinutes;

  const EmergencyFacility({
    required this.id,
    required this.name,
    required this.type,
    required this.address,
    required this.phone,
    required this.latitude,
    required this.longitude,
    required this.openStatus,
    this.isOpen24Hours = false,
    this.capabilities = const [],
    required this.distanceKm,
    required this.travelTimeMinutes,
  });

  factory EmergencyFacility.fromJson(Map<String, dynamic> json) {
    return EmergencyFacility(
      id: json['id'] as String? ?? 'fac-${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Emergency Facility',
      type: json['type'] as String? ?? 'Emergency Department',
      address: json['address'] as String? ?? 'Regional Medical Center',
      phone: json['phone'] as String? ?? '+1-555-0199',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      openStatus: json['openStatus'] as String? ?? (json['isOpen24Hours'] == true ? 'Open 24/7' : 'Open Now'),
      isOpen24Hours: json['isOpen24Hours'] as bool? ?? false,
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
      travelTimeMinutes: (json['travelTimeMinutes'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'address': address,
      'phone': phone,
      'latitude': latitude,
      'longitude': longitude,
      'openStatus': openStatus,
      'isOpen24Hours': isOpen24Hours,
      'capabilities': capabilities,
      'distanceKm': distanceKm,
      'travelTimeMinutes': travelTimeMinutes,
    };
  }
}
