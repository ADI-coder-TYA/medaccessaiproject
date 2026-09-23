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

  const nearbyResult = EmergencyFacilityService.getNearbyFacilities(campusLat, campusLng, 20.0);
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

  console.log('\n================================================================');
  console.log(`📊 Emergency Facility Test Summary: ${passed} passed, ${failed} failed`);
  console.log('================================================================\n');

  if (failed > 0) {
    process.exit(1);
  }
}

runEmergencyFacilityTests().catch((err) => {
  console.error('Fatal test error:', err);
  process.exit(1);
});
