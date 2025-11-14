import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../widgets/ambulance_card.dart';
import '../models/ambulance.dart';

class AmbulanceListScreen extends StatelessWidget {
  final FirebaseService firebaseService = FirebaseService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Available Ambulances")),
      body: StreamBuilder<List<Ambulance>>(
        stream: firebaseService.getAmbulancesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text("No ambulances found"));
          }

          final ambulances = snapshot.data!;
          return ListView.builder(
            itemCount: ambulances.length,
            itemBuilder: (context, index) {
              return AmbulanceCard(ambulance: ambulances[index]);
            },
          );
        },
      ),
    );
  }
}
