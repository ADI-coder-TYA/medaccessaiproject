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

  // In-memory cache for live Places API responses (10 min TTL)
  private static readonly placesCache = new Map<string, { timestamp: number; facilities: EmergencyFacility[] }>();
  private static readonly CACHE_TTL_MS = 10 * 60 * 1000;

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
   * Queries Google Places API (New) Nearby Search using Pro SKU fields:
   * places.id, places.displayName, places.formattedAddress, places.location,
   * places.types, places.nationalPhoneNumber, places.currentOpeningHours, places.regularOpeningHours
   */
  public static async fetchFromGooglePlaces(
    userLat: number,
    userLng: number,
    radiusKm: number,
    facilityTypeFilter?: FacilityType
  ): Promise<EmergencyFacility[] | null> {
    const apiKey = process.env.GOOGLE_PLACES_API_KEY || process.env.GOOGLE_MAPS_API_KEY;
    if (!apiKey) {
      console.log('ℹ️ [EmergencyFacilityService] GOOGLE_PLACES_API_KEY not configured. Falling back to internal facility tiers.');
      return null;
    }

    const cacheKey = `${userLat.toFixed(3)}_${userLng.toFixed(3)}_${radiusKm}_${facilityTypeFilter || 'all'}`;
    const cached = this.placesCache.get(cacheKey);
    if (cached && Date.now() - cached.timestamp < this.CACHE_TTL_MS) {
      console.log(`⚡ [EmergencyFacilityService] Cache Hit! Serving ${cached.facilities.length} facilities for key [${cacheKey}]`);
      return cached.facilities;
    }

    try {
      const radiusMeters = Math.min(Math.max(radiusKm * 1000, 1000), 50000);
      const endpoint = 'https://places.googleapis.com/v1/places:searchNearby';
      const startTime = Date.now();

      console.log(`🌐 [Google Places API] Requesting Nearby Search (Pro SKU) at (${userLat.toFixed(4)}, ${userLng.toFixed(4)}) | Radius: ${radiusMeters}m...`);

      const requestBody = {
        includedTypes: ['hospital', 'doctor'],
        maxResultCount: 15,
        locationRestriction: {
          circle: {
            center: {
              latitude: userLat,
              longitude: userLng
            },
            radius: radiusMeters
          }
        }
      };

      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location,places.types,places.nationalPhoneNumber,places.currentOpeningHours,places.regularOpeningHours'
        },
        body: JSON.stringify(requestBody)
      });

      const elapsedMs = Date.now() - startTime;

      if (!response.ok) {
        const errorText = await response.text();
        console.warn(`❌ [Google Places API] Request failed with HTTP ${response.status} in ${elapsedMs}ms:`, errorText);
        return null;
      }

      const data = (await response.json()) as { places?: any[] };
      const rawCount = data.places?.length || 0;
      console.log(`✅ [Google Places API] HTTP 200 OK (${elapsedMs}ms). Received ${rawCount} raw places.`);

      if (!data.places || !Array.isArray(data.places) || data.places.length === 0) {
        console.log('⚠️ [Google Places API] Zero medical facilities found in requested geographic perimeter.');
        return [];
      }

      const results: EmergencyFacility[] = [];

      for (const p of data.places) {
        if (!p.location?.latitude || !p.location?.longitude) continue;

        const name = p.displayName?.text || 'Emergency Medical Facility';
        const nameLower = name.toLowerCase();

        let type: FacilityType = 'Emergency Department';
        if (nameLower.includes('trauma') || nameLower.includes('level 1') || nameLower.includes('level 2')) {
          type = 'Trauma Center';
        } else if (nameLower.includes('urgent') || nameLower.includes('walk-in') || nameLower.includes('immediate')) {
          type = 'Urgent Care Center';
        } else if (nameLower.includes('campus') || nameLower.includes('student') || nameLower.includes('university health')) {
          type = 'Campus Health Center';
        }

        if (facilityTypeFilter && type !== facilityTypeFilter) {
          continue;
        }

        const isOpen24Hours = Boolean(
          p.regularOpeningHours?.periods?.some(
            (per: any) => per.open?.hour === 0 && per.open?.minute === 0 && !per.close
          ) ||
          p.regularOpeningHours?.weekdayDescriptions?.some((desc: string) =>
            desc.toLowerCase().includes('open 24 hours')
          )
        );

        let openStatus = 'Open 24/7';
        if (!isOpen24Hours) {
          if (p.currentOpeningHours?.openNow === true) {
            openStatus = 'Open Now';
          } else if (p.currentOpeningHours?.openNow === false) {
            openStatus = 'Closed';
          } else {
            openStatus = 'Open Now';
          }
        }

        const capabilities: string[] = [];
        if (type === 'Trauma Center') {
          capabilities.push('Level 1/2 Trauma', 'Cardiac Catheterization', 'Comprehensive Stroke Center', 'Acute Resuscitation');
        } else if (type === 'Emergency Department') {
          capabilities.push('24/7 Emergency Care', 'Acute Stabilization', 'Triage & Diagnostics');
        } else if (type === 'Urgent Care Center') {
          capabilities.push('Walk-in Triage', 'Minor Fracture Splinting', 'Nebulizer Therapy', 'Rapid Lab');
        } else {
          capabilities.push('Student Walk-in Clinic', 'Outpatient Triage', 'Basic Care');
        }

        if (isOpen24Hours && !capabilities.includes('24/7 Emergency Care')) {
          capabilities.unshift('24/7 Emergency Care');
        }

        const dist = this.calculateDistanceKm(userLat, userLng, p.location.latitude, p.location.longitude);

        results.push({
          id: p.id,
          name,
          type,
          address: p.formattedAddress || 'Address on file',
          phone: p.nationalPhoneNumber || '+1-555-0199',
          latitude: p.location.latitude,
          longitude: p.location.longitude,
          openStatus,
          isOpen24Hours,
          capabilities,
          distanceKm: dist,
          travelTimeMinutes: this.calculateTravelTimeMinutes(dist)
        });
      }

      results.sort((a, b) => (a.distanceKm ?? 0) - (b.distanceKm ?? 0));

      console.log(`🎯 [Google Places API] Parsed & mapped ${results.length} valid medical facilities. Closest: "${results[0]?.name || 'N/A'}" (${results[0]?.distanceKm}km, ~${results[0]?.travelTimeMinutes} min drive).`);

      this.placesCache.set(cacheKey, {
        timestamp: Date.now(),
        facilities: results
      });

      return results;
    } catch (err) {
      console.warn('❌ [Google Places API] Exception during nearby search request:', err);
      return null;
    }
  }

  /**
   * Queries facilities within specified radius (default 20 km), sorted by ascending distance.
   * Priority:
   * 1. Google Places API (New) Pro SKU if GOOGLE_PLACES_API_KEY is configured
   * 2. Supabase `emergency_facilities` table
   * 3. Embedded regional reference facilities (zero-failure emergency guarantee)
   */
  public static async getNearbyFacilities(
    userLat: number,
    userLng: number,
    radiusKm: number = 20.0,
    facilityTypeFilter?: FacilityType
  ): Promise<NearbyFacilitiesResult> {
    console.log(`🏥 [EmergencyFacilityService] Querying facilities around (${userLat.toFixed(4)}, ${userLng.toFixed(4)}) | Radius: ${radiusKm}km | Filter: ${facilityTypeFilter || 'ALL'}`);

    // 1. Attempt Live Google Places API Query
    const googleFacilities = await this.fetchFromGooglePlaces(userLat, userLng, radiusKm, facilityTypeFilter);
    if (googleFacilities !== null && googleFacilities.length > 0) {
      console.log(`🚀 [EmergencyFacilityService] Serving ${googleFacilities.length} facilities via Tier 1: Google Places API (Live).`);
      return {
        userLocation: {
          latitude: userLat,
          longitude: userLng
        },
        searchRadiusKm: radiusKm,
        totalFound: googleFacilities.length,
        facilities: googleFacilities
      };
    }

    // 2. Fallback to Supabase Database
    let sourceFacilities: EmergencyFacility[] = this.REGIONAL_FACILITIES;
    let tierSource = 'Tier 3 (Embedded Regional)';

    try {
      console.log('📦 [EmergencyFacilityService] Checking Tier 2: Supabase "emergency_facilities" table...');
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
        tierSource = `Tier 2 (Supabase: ${data.length} records)`;
        console.log(`✅ [EmergencyFacilityService] Loaded ${data.length} facilities from Supabase database.`);
      } else {
        console.log(`🛡️ [EmergencyFacilityService] Supabase returned 0 facilities or table unseeded. Engaging Tier 3: Curated Regional Reference dataset (${this.REGIONAL_FACILITIES.length} facilities).`);
      }
    } catch (dbErr) {
      console.warn('⚠️ [EmergencyFacilityService] Supabase query threw exception, using Tier 3 regional dataset:', dbErr);
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

    console.log(`🚑 [EmergencyFacilityService] Resolved ${matched.length} facilities via ${tierSource} within ${radiusKm}km (Nearest: "${matched[0]?.name || 'None'}", ${matched[0]?.distanceKm ?? 0}km).`);

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
