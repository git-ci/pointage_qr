class Site {
  final int id;
  final String name;
  final String? city;
  final String? address;
  final double? latitude;
  final double? longitude;
  final int radiusMeters;
  final bool active;
  final bool gpsConfigured;
  final String terminalUrl;
  final String token;
  final String? deviceId;
  final String? deviceLabel;
  final bool deviceBound;
  final String checkinDeadline; // Format "HH:MM", défaut "10:00"

  Site({
    required this.id,
    required this.name,
    this.city,
    this.address,
    this.latitude,
    this.longitude,
    required this.radiusMeters,
    required this.active,
    required this.gpsConfigured,
    required this.terminalUrl,
    required this.token,
    this.deviceId,
    this.deviceLabel,
    required this.deviceBound,
    this.checkinDeadline = '10:00',
  });

  factory Site.fromJson(Map<String, dynamic> json) {
    return Site(
      id: json['id'] as int,
      name: json['name'] as String,
      city: json['city'] as String?,
      address: json['address'] as String?,
      latitude: json['latitude'] != null
          ? (json['latitude'] as num).toDouble()
          : null,
      longitude: json['longitude'] != null
          ? (json['longitude'] as num).toDouble()
          : null,
      radiusMeters: json['radius_meters'] as int? ?? 50,
      active: json['active'] as bool? ?? true,
      gpsConfigured: json['gps_configured'] as bool? ?? false,
      terminalUrl: json['terminal_url'] as String? ?? '',
      token: json['token'] as String? ?? '',
      deviceId: json['device_id'] as String?,
      deviceLabel: json['device_label'] as String?,
      deviceBound: json['device_bound'] as bool? ?? false,
      checkinDeadline: json['checkin_deadline'] as String? ?? '10:00',
    );
  }
}
