import 'package:flutter/material.dart';
import '../models/ambulance.dart';

class AmbulanceCard extends StatelessWidget {
  final Ambulance ambulance;

  AmbulanceCard({required this.ambulance});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(8),
      child: ListTile(
        leading: Icon(
          Icons.local_hospital,
          color: ambulance.status == "available" ? Colors.green : Colors.red,
        ),
        title: Text("Ambulance ID: ${ambulance.id}"),
        subtitle: Text(
          "Status: ${ambulance.status ?? "unknown"}\n"
          "Lat: ${ambulance.latitude?.toStringAsFixed(4)}, "
          "Lon: ${ambulance.longitude?.toStringAsFixed(4)}",
        ),
        trailing: ambulance.distance != null
            ? Text("${ambulance.distance!.toStringAsFixed(2)} km")
            : null,
      ),
    );
  }
}
