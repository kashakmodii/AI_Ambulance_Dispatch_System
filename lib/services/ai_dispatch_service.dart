import '../models/ambulance.dart';
import '../utils/location_utils.dart';

class AIDispatchService {
  Ambulance? findNearestAmbulance(
      List<Ambulance> ambulances, double patientLat, double patientLon) {
    Ambulance? nearest;
    double minDistance = double.infinity;

    for (var amb in ambulances) {
      if (amb.status != "available") continue;

      final dist = LocationUtils.calculateDistance(
        patientLat,
        patientLon,
        amb.latitude ?? 0,
        amb.longitude ?? 0,
      );

      if (dist < minDistance) {
        minDistance = dist;
        amb.distance = dist;
        nearest = amb;
      }
    }
    return nearest;
  }
}
