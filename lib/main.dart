import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'screens/login_screen.dart'; // updated to login screen
import 'firebase_options.dart';

// Create a local notifications plugin instance
final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ---- Initialize local notifications ----
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await localNotifications.initialize(initSettings);

  // ---- Ask FCM for permission (iOS/macOS) ----
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // ---- Listen for foreground messages ----
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final notif = message.notification;
    if (notif != null) {
      localNotifications.show(
        0,
        notif.title ?? 'Ambulance update',
        notif.body ?? '',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'ai_ambulance_channel',
            'AI Ambulance',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    }
  });

  runApp(const AIAmbulanceApp());
}

class AIAmbulanceApp extends StatelessWidget {
  const AIAmbulanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Ambulance Dispatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.red),
      home: const LoginScreen(), // start with login
    );
  }
}
