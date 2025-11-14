import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ambulance.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // === Existing method for ambulances ===
  Stream<List<Ambulance>> getAmbulancesStream() {
    return _firestore.collection("ambulances").snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return Ambulance.fromFirestore(doc.data(), doc.id);
      }).toList();
    });
  }

  // === NEW method for My Rides ===
Stream<QuerySnapshot<Map<String, dynamic>>> getAllRequests() {
  return FirebaseFirestore.instance
      .collection('requests')
      .orderBy('createdAt', descending: true)
      .snapshots();
}

}
