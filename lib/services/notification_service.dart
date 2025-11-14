import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/ambulance.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  NotificationService() {
    final android = AndroidInitializationSettings('@mipmap/ic_launcher');
    final ios = DarwinInitializationSettings();
    _notifications.initialize(InitializationSettings(android: android, iOS: ios));
  }

  void showAmbulanceNearby(Ambulance amb) {
    _notifications.show(
      0,
      "Nearest Ambulance Found",
      "Ambulance ${amb.id} is only ${amb.distance?.toStringAsFixed(2)} km away!",
      const NotificationDetails(
        android: AndroidNotificationDetails("channelId", "channelName",
            importance: Importance.max, priority: Priority.high),
      ),
    );
  }
}
