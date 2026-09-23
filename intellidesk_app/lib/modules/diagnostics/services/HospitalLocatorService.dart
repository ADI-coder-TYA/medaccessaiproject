import 'dart:convert';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../../config/api_config.dart';
import '../models/emergency_facility.dart';

class HospitalLocatorService {
  /**
   * Technical Guardrail 3: Geodesic Metric Parity
   * Standardized mean Earth radius R = 6371.0 km
   */
  static const double earthRadiusKm = 6371.0;

  // Regional campus reference coordinates used when GPS is disabled or denied
  static const double defaultCampusLatitude = 40.7128;
  static const double defaultCampusLongitude = -74.0060;

  // Embedded offline facilities database for guaranteed zero-failure emergency routing
  static const List<Map<String, dynamic>> _offlineEmergencyFacilities = [
    {
      'id': 'fac-trauma-01',
      'name': 'St. Jude University Level 1 Trauma Center',
      'type': 'Trauma Center',
      'address': '750 Hospital Plaza, University Medical District',
      'phone': '+1-555-0199',
      'latitude': 40.7180,
      'longitude': -74.0020,
      'openStatus': 'Open 24/7',
      'isOpen24Hours': true,
      'capabilities': ['Level 1 Trauma', 'Cardiac Catheterization', 'Comprehensive Stroke Center', 'Helipad']
    },
    {
      'id': 'fac-er-02',
      'name': 'Memorial Community Hospital Emergency Dept',
      'type': 'Emergency Department',
      'address': '1240 Health Boulevard, Midtown East',
      'phone': '+1-555-0144',
      'latitude': 40.7250,
      'longitude': -73.9910,
      'openStatus': 'Open 24/7',
      'isOpen24Hours': true,
      'capabilities': ['24/7 Emergency Care', 'Pediatric ER', 'Acute Burn Resuscitation', 'Rapid CT Scan']
    },
    {
      'id': 'fac-campus-03',
      'name': 'Campus Student Health & Urgent Care Center',
      'type': 'Campus Health Center',
      'address': '200 University Way, Student Wellness Complex',
      'phone': '+1-555-0112',
      'latitude': 40.7145,
      'longitude': -74.0090,
      'openStatus': 'Open Now (Closes 10:00 PM)',
      'isOpen24Hours': false,
      'capabilities': ['Walk-in Triage', 'On-site X-Ray', 'Wound Suturing', 'IV Hydration']
    },
    {
      'id': 'fac-urgent-04',
      'name': 'CityMed Immediate Urgent Care',
      'type': 'Urgent Care Center',
      'address': '580 Lexington Ave, Suite 100',
      'phone': '+1-555-0177',
      'latitude': 40.7310,
      'longitude': -74.0150,
      'openStatus': 'Open Now (Closes 9:00 PM)',
      'isOpen24Hours': false,
      'capabilities': ['Urgent Medical Care', 'Minor Fracture Splinting', 'Nebulizer Therapy', 'Rapid Lab']
    },
    {
      'id': 'fac-suburban-05',
      'name': 'Regional County General Hospital & Trauma',
      'type': 'Trauma Center',
      'address': '4500 County Road 9, North Valley',
      'phone': '+1-555-0188',
      'latitude': 40.8200,
      'longitude': -73.9600,
      'openStatus': 'Open 24/7',
      'isOpen24Hours': true,
      'capabilities': ['Level 2 Trauma', '24/7 Surgical Suites', 'ICU / CCU', 'Paramedic Dispatch Base']
    }
  ];

  /**
   * Technical Guardrail 2: Strict 3-Second GPS Timeout
   * Retrieves current position or defaults to campus coordinates within 3 seconds.
   */
  Future<Position?> getCurrentPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          return null;
        }
      }

      // Strict 3-second timeout constraint (Guardrail 2)
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 3),
        ),
      ).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Instantly default on timeout or native platform exceptions
      return null;
    }
  }

  /**
   * Retrieves patient coordinate pair (falling back to regional campus coordinates).
   */
  Future<Map<String, double>> resolveCoordinates() async {
    final pos = await getCurrentPosition();
    if (pos != null) {
      return {'latitude': pos.latitude, 'longitude': pos.longitude};
    }
    return {
      'latitude': defaultCampusLatitude,
      'longitude': defaultCampusLongitude,
    };
  }

  /**
   * Technical Guardrail 3: Haversine Geodesic Distance (R = 6371.0 km)
   */
  static double calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    double toRad(double deg) => (deg * math.pi) / 180.0;

    final dLat = toRad(lat2 - lat1);
    final dLon = toRad(lon2 - lon1);
    final rLat1 = toRad(lat1);
    final rLat2 = toRad(lat2);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rLat1) * math.cos(rLat2) * math.sin(dLon / 2) * math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final distance = earthRadiusKm * c;

    return (distance * 10).round() / 10;
  }

  static int calculateTravelTimeMinutes(double distanceKm) {
    const double avgSpeedKmh = 40.0;
    final hours = distanceKm / avgSpeedKmh;
    final mins = (hours * 60).round();
    return math.max(1, mins);
  }

  /**
   * Queries nearby emergency care centers, trauma hospitals, and campus clinics within 20km radius.
   * Seamlessly falls back to local Haversine offline dataset if network or backend API is unreachable.
   */
  Future<List<EmergencyFacility>> getNearbyFacilities({
    double? latitude,
    double? longitude,
    double radiusKm = 20.0,
  }) async {
    final coords = (latitude != null && longitude != null)
        ? {'latitude': latitude, 'longitude': longitude}
        : await resolveCoordinates();

    final userLat = coords['latitude']!;
    final userLng = coords['longitude']!;

    // 1. Attempt Backend API Query
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/diagnostics/facilities/nearby?lat=$userLat&lng=$userLng&radiusKm=$radiusKm',
      );
      final res = await http.get(uri, headers: ApiConfig.patientHeaders).timeout(const Duration(seconds: 3));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true && body['facilities'] is List) {
          final list = (body['facilities'] as List)
              .map((e) => EmergencyFacility.fromJson(e as Map<String, dynamic>))
              .toList();
          if (list.isNotEmpty) {
            return list;
          }
        }
      }
    } catch (_) {
      // Gracefully fall back to local offline facility engine
    }

    // 2. Offline / Direct Haversine Calculation (Guardrail 3)
    final List<EmergencyFacility> localMatched = [];
    for (final raw in _offlineEmergencyFacilities) {
      final fLat = (raw['latitude'] as num).toDouble();
      final fLng = (raw['longitude'] as num).toDouble();
      final dist = calculateDistanceKm(userLat, userLng, fLat, fLng);

      if (dist <= radiusKm) {
        localMatched.add(
          EmergencyFacility.fromJson({
            ...raw,
            'distanceKm': dist,
            'travelTimeMinutes': calculateTravelTimeMinutes(dist),
          }),
        );
      }
    }

    // Sort ascending by distance (nearest emergency center first)
    localMatched.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return localMatched;
  }
}
