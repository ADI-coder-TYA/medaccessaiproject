import { supabase } from '../../../config/supabase.js';

export type FacilityType = 
  | 'Trauma Center'
  | 'Emergency Department'
  | 'Urgent Care Center'
  | 'Campus Health Center';

export interface EmergencyFacility {
  id: string;
  name: string;
  type: FacilityType;
  address: string;
  phone: string;
  latitude: number;
  longitude: number;
  openStatus: string; // e.g. "Open 24/7", "Open Now"
  isOpen24Hours: boolean;
  capabilities: string[];
  distanceKm?: number;
  travelTimeMinutes?: number;
}

export interface NearbyFacilitiesResult {
  userLocation: {
    latitude: number;
    longitude: number;
  };
  searchRadiusKm: number;
  totalFound: number;
  facilities: EmergencyFacility[];
}

export class EmergencyFacilityService {
  /**
   * Technical Guardrail 3: Geodesic Metric Parity
   * Standardized mean Earth radius R = 6371.0 km
   */
  public static readonly EARTH_RADIUS_KM = 6371.0;

  // Average urban/suburban transit velocity (40 km/h) for driving travel time estimations
  private static readonly AVERAGE_SPEED_KMH = 40.0;

  // Curated regional reference facilities (Metropolitan & Campus Health Network)
  private static readonly REGIONAL_FACILITIES: EmergencyFacility[] = [
    {
      id: 'fac-trauma-01',
      name: 'St. Jude University Level 1 Trauma Center',
      type: 'Trauma Center',
      address: '750 Hospital Plaza, University Medical District',
      phone: '+1-555-0199',
      latitude: 40.7180,
      longitude: -74.0020,
      openStatus: 'Open 24/7',
      isOpen24Hours: true,
      capabilities: ['Level 1 Trauma', 'Cardiac Catheterization', 'Comprehensive Stroke Center', 'Helipad']
    },
    {
      id: 'fac-er-02',
      name: 'Memorial Community Hospital Emergency Dept',
      type: 'Emergency Department',
      address: '1240 Health Boulevard, Midtown East',
      phone: '+1-555-0144',
      latitude: 40.7250,
      longitude: -73.9910,
      openStatus: 'Open 24/7',
      isOpen24Hours: true,
      capabilities: ['24/7 Emergency Care', 'Pediatric ER', 'Acute Burn Resuscitation', 'Rapid CT Scan']
    },
    {
      id: 'fac-campus-03',
      name: 'Campus Student Health & Urgent Care Center',
      type: 'Campus Health Center',
      address: '200 University Way, Student Wellness Complex',
      phone: '+1-555-0112',
      latitude: 40.7145,
      longitude: -74.0090,
      openStatus: 'Open Now (Closes 10:00 PM)',
      isOpen24Hours: false,
      capabilities: ['Walk-in Triage', 'On-site X-Ray', 'Wound Suturing', 'IV Hydration']
    },
    {
      id: 'fac-urgent-04',
      name: 'CityMed Immediate Urgent Care',
      type: 'Urgent Care Center',
      address: '580 Lexington Ave, Suite 100',
      phone: '+1-555-0177',
      latitude: 40.7310,
      longitude: -74.0150,
      openStatus: 'Open Now (Closes 9:00 PM)',
      isOpen24Hours: false,
      capabilities: ['Urgent Medical Care', 'Minor Fracture Splinting', 'Nebulizer Therapy', 'Rapid Lab']
    },
    {
      id: 'fac-suburban-05',
      name: 'Regional County General Hospital & Trauma',
      type: 'Trauma Center',
      address: '4500 County Road 9, North Valley',
      phone: '+1-555-0188',
      latitude: 40.8200,
      longitude: -73.9600,
      openStatus: 'Open 24/7',
      isOpen24Hours: true,
      capabilities: ['Level 2 Trauma', '24/7 Surgical Suites', 'ICU / CCU', 'Paramedic Dispatch Base']
    },
    {
      id: 'fac-distant-06',
      name: 'Out-of-County Specialized Burn Center',
      type: 'Emergency Department',
      address: '9800 State Highway 44, Far Hills',
      phone: '+1-555-0155',
      latitude: 41.1500, // > 40km away from central coords
      longitude: -73.8000,
      openStatus: 'Open 24/7',
      isOpen24Hours: true,
      capabilities: ['Regional Burn Center', 'Hyperbaric Oxygen']
    }
  ];

  /**
   * Technical Guardrail 3: Haversine Geodesic Distance Formula (R = 6371.0 km)
   */
  public static calculateDistanceKm(
    lat1: number,
    lon1: number,
    lat2: number,
    lon2: number
  ): number {
    const toRad = (deg: number) => (deg * Math.PI) / 180.0;

    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const rLat1 = toRad(lat1);
    const rLat2 = toRad(lat2);

    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(rLat1) * Math.cos(rLat2) * Math.sin(dLon / 2) * Math.sin(dLon / 2);

    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const distance = this.EARTH_RADIUS_KM * c;

    return Math.round(distance * 10) / 10;
  }

  /**
   * Estimates transit travel time in minutes based on 40 km/h average velocity.
   */
  public static calculateTravelTimeMinutes(distanceKm: number): number {
    const hours = distanceKm / this.AVERAGE_SPEED_KMH;
    const minutes = Math.round(hours * 60);
    return Math.max(1, minutes);
  }

  /**
   * Queries facilities within specified radius (default 20 km), sorted by ascending distance.
   * Checks Supabase `emergency_facilities` table with fallback to embedded regional facilities.
   */
  public static async getNearbyFacilities(
    userLat: number,
    userLng: number,
    radiusKm: number = 20.0,
    facilityTypeFilter?: FacilityType
  ): Promise<NearbyFacilitiesResult> {
    let sourceFacilities: EmergencyFacility[] = this.REGIONAL_FACILITIES;

    try {
      const { data, error } = await supabase
        .from('emergency_facilities')
        .select('*');

      if (!error && Array.isArray(data) && data.length > 0) {
        sourceFacilities = data.map((row: any) => ({
          id: row.id,
          name: row.name,
          type: row.type as FacilityType,
          address: row.address,
          phone: row.phone,
          latitude: Number(row.latitude),
          longitude: Number(row.longitude),
          openStatus: row.open_status || row.openStatus || 'Open 24/7',
          isOpen24Hours: Boolean(row.is_open_24_hours ?? row.isOpen24Hours ?? true),
          capabilities: Array.isArray(row.capabilities) ? row.capabilities : []
        }));
      }
    } catch (_) {
      // Fallback to regional facilities
    }

    const matched: EmergencyFacility[] = [];

    for (const fac of sourceFacilities) {
      if (facilityTypeFilter && fac.type !== facilityTypeFilter) {
        continue;
      }

      const dist = this.calculateDistanceKm(userLat, userLng, fac.latitude, fac.longitude);

      if (dist <= radiusKm) {
        matched.push({
          ...fac,
          distanceKm: dist,
          travelTimeMinutes: this.calculateTravelTimeMinutes(dist)
        });
      }
    }

    // Sort ascending by distance (nearest emergency care first)
    matched.sort((a, b) => (a.distanceKm ?? 0) - (b.distanceKm ?? 0));

    return {
      userLocation: {
        latitude: userLat,
        longitude: userLng
      },
      searchRadiusKm: radiusKm,
      totalFound: matched.length,
      facilities: matched
    };
  }

  /**
   * Exposes raw facility dataset for testing and inspection.
   */
  public static getAllFacilities(): EmergencyFacility[] {
    return [...this.REGIONAL_FACILITIES];
  }
}
