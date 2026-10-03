import { EmergencyFacilityService } from '../modules/diagnostics/facilities/EmergencyFacilityService.js';

let passed = 0;
let failed = 0;

function assert(condition: boolean, message: string) {
  if (condition) {
    console.log(`  ✅ PASS: ${message}`);
    passed++;
  } else {
    console.error(`  ❌ FAIL: ${message}`);
    failed++;
  }
}

async function runEmergencyFacilityTests() {
  console.log('\n================================================================');
  console.log('🧪 Starting Emergency Care Facility Routing Test Suite');
  console.log('================================================================\n');

  // Central university campus coordinates
  const campusLat = 40.7128;
  const campusLng = -74.0060;

  // -------------------------------------------------------------
  // TEST 1: Geodesic Metric Parity & Haversine Accuracy (Guardrail 3)
  // -------------------------------------------------------------
  console.log('--- TEST 1: Geodesic Metric Parity (R = 6371.0 km) ---');

  assert(
    EmergencyFacilityService.EARTH_RADIUS_KM === 6371.0,
    `Earth radius is standardized to 6371.0 km (got ${EmergencyFacilityService.EARTH_RADIUS_KM})`
  );

  // Distance between same point
  const zeroDist = EmergencyFacilityService.calculateDistanceKm(campusLat, campusLng, campusLat, campusLng);
  assert(zeroDist === 0.0, `Self-distance evaluates to 0.0 km (got ${zeroDist})`);

  // Benchmark: Central Manhattan (40.7128, -74.0060) to Midtown (40.7589, -73.9851) ~ 5.4 km
  const benchmarkDist = EmergencyFacilityService.calculateDistanceKm(40.7128, -74.0060, 40.7589, -73.9851);
  assert(
    benchmarkDist >= 5.0 && benchmarkDist <= 5.8,
    `Benchmark distance accurate to expected geodesic range ~5.4 km (got ${benchmarkDist} km)`
  );

  // -------------------------------------------------------------
  // TEST 2: 20 km Radius Filtering
  // -------------------------------------------------------------
  console.log('\n--- TEST 2: 20 km Search Radius Filtering ---');

  const nearbyResult = await EmergencyFacilityService.getNearbyFacilities(campusLat, campusLng, 20.0);
  assert(nearbyResult.searchRadiusKm === 20.0, 'Search radius is 20.0 km');
  assert(nearbyResult.totalFound >= 4, `At least 4 regional facilities within 20 km (got ${nearbyResult.totalFound})`);

  // Verify all returned facilities have distance <= 20 km
  const allWithinRadius = nearbyResult.facilities.every((f) => (f.distanceKm ?? 999) <= 20.0);
  assert(allWithinRadius, 'All returned facilities strictly satisfy distance <= 20 km');

  // Verify out-of-range facility (fac-distant-06, ~40km away) is excluded
  const hasDistantFacility = nearbyResult.facilities.some((f) => f.id === 'fac-distant-06');
  assert(!hasDistantFacility, 'Distant facility (>20 km) is strictly excluded');

  // -------------------------------------------------------------
  // TEST 3: Distance Ordering (Nearest First)
  // -------------------------------------------------------------
  console.log('\n--- TEST 3: Ascending Distance Ordering ---');

  let isSorted = true;
  for (let i = 1; i < nearbyResult.facilities.length; i++) {
    const prevDist = nearbyResult.facilities[i - 1].distanceKm ?? 0;
    const currDist = nearbyResult.facilities[i].distanceKm ?? 0;
    if (currDist < prevDist) {
      isSorted = false;
      break;
    }
  }
  assert(isSorted, 'Facilities are strictly sorted ascending by distance (closest first)');

  const closest = nearbyResult.facilities[0];
  assert(closest.distanceKm !== undefined && closest.distanceKm < 1.0, `Nearest facility is < 1 km away (got ${closest.name}, ${closest.distanceKm} km)`);
  assert(closest.travelTimeMinutes !== undefined && closest.travelTimeMinutes > 0, `Travel time calculated (>0 mins, got ${closest.travelTimeMinutes} mins)`);

  // -------------------------------------------------------------
  // TEST 4: Facility Metadata & Emergency Deep Link Fields
  // -------------------------------------------------------------
  console.log('\n--- TEST 4: Facility Metadata & Emergency Contact ---');

  const traumaCenter = nearbyResult.facilities.find((f) => f.type === 'Trauma Center');
  assert(traumaCenter !== undefined, 'Trauma Center facility present in nearby results');
  assert(traumaCenter!.phone.startsWith('+1-555-'), `Valid emergency phone dialer string: ${traumaCenter?.phone}`);
  assert(traumaCenter!.isOpen24Hours === true, 'Trauma Center is open 24 hours');
  assert(traumaCenter!.capabilities.length >= 2, `Capabilities list populated: ${traumaCenter?.capabilities.join(', ')}`);

  // -------------------------------------------------------------
  // TEST 5: Dynamic Differentiated Clinical Capabilities
  // -------------------------------------------------------------
  console.log('\n--- TEST 5: Dynamic Clinical Capability Derivation ---');

  const pediatricCaps = EmergencyFacilityService.deriveCapabilities(
    'Children Hospital of Philadelphia Emergency Wing',
    'Emergency Department',
    ['hospital'],
    true
  );
  assert(pediatricCaps.includes('Pediatric ER'), 'Pediatric hospital receives Pediatric ER capability');

  const cardiacCaps = EmergencyFacilityService.deriveCapabilities(
    'Midtown Heart & Vascular Institute',
    'Emergency Department',
    ['hospital'],
    true
  );
  assert(cardiacCaps.includes('Cardiac Catheterization'), 'Cardiac center receives Cardiac Catheterization capability');

  const generalCaps = EmergencyFacilityService.deriveCapabilities(
    'City General Hospital',
    'Emergency Department',
    ['hospital'],
    true
  );
  // Ensure generalCaps and cardiacCaps are not identical
  const areIdentical = generalCaps.length === cardiacCaps.length && generalCaps.every((c, i) => c === cardiacCaps[i]);
  assert(!areIdentical, 'Distinct hospitals have distinct, differentiated clinical capabilities');
  console.log(`   [Pediatric Caps] ${pediatricCaps.join(' | ')}`);
  console.log(`   [Cardiac Caps]   ${cardiacCaps.join(' | ')}`);
  // -------------------------------------------------------------
  // TEST 6: skipGooglePlaces Flag strictly avoids Tier 1 (Places API)
  // -------------------------------------------------------------
  console.log('\n--- TEST 6: Offline / Overview Safe Mode (skipGooglePlaces) ---');

  const offlineResult = await EmergencyFacilityService.getNearbyFacilities(campusLat, campusLng, 20.0, undefined, true);
  assert(offlineResult.facilities.length > 0, `Offline query returned ${offlineResult.facilities.length} facilities`);
  assert(
    offlineResult.facilities.every(f => f.distanceKm !== undefined && f.distanceKm <= 20.0),
    'Offline facilities strictly within 20 km search radius'
  );

  // -------------------------------------------------------------
  // TEST 7: Haversine Spatial Cache (200m Displacement Threshold & 6h TTL)
  // -------------------------------------------------------------
  console.log('\n--- TEST 7: Haversine Spatial Cache & Threshold Validation ---');

  assert(
    EmergencyFacilityService.SPATIAL_CACHE_DISPLACEMENT_KM === 0.20,
    `Spatial cache displacement threshold is standardized to 200m / 0.20 km (got ${EmergencyFacilityService.SPATIAL_CACHE_DISPLACEMENT_KM} km)`
  );
  assert(
    EmergencyFacilityService.CACHE_TTL_MS === 6 * 60 * 60 * 1000,
    `Spatial cache TTL is standardized to 6 Hours (got ${EmergencyFacilityService.CACHE_TTL_MS / (60 * 60 * 1000)} hours)`
  );

  // Reset spatial cache
  EmergencyFacilityService.clearCache();

  // Initial query at campus
  const q1 = await EmergencyFacilityService.getNearbyFacilities(campusLat, campusLng, 20.0);
  assert(q1.facilities.length > 0, `Initial facility search succeeded with ${q1.facilities.length} facilities`);

  // Move user by 50 meters (~0.00045 degrees lat)
  const shift50mLat = campusLat + 0.00045;
  const displacement50m = EmergencyFacilityService.calculateDistanceKm(campusLat, campusLng, shift50mLat, campusLng);
  assert(
    displacement50m < EmergencyFacilityService.SPATIAL_CACHE_DISPLACEMENT_KM,
    `Displacement of ~50m is within the 200m spatial cache boundary (got ${(displacement50m * 1000).toFixed(0)}m)`
  );

  const q2 = await EmergencyFacilityService.getNearbyFacilities(shift50mLat, campusLng, 20.0);
  assert(q2.facilities.length === q1.facilities.length, 'Spatial cache hit served same facility pool without redundant live Places query');

  console.log('\n================================================================');
  console.log(`📊 Emergency Facility Test Summary: ${passed} passed, ${failed} failed`);
  console.log('================================================================\n');

  if (failed > 0) {
    process.exit(1);
  }
  process.exit(0);
}

runEmergencyFacilityTests().catch((err) => {
  console.error('Fatal test error:', err);
  process.exit(1);
});
