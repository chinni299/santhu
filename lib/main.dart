import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'app.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint("FCM Background Message received: ${message.messageId}");
  } catch (e) {
    debugPrint("FCM Background Handler error: $e");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    debugPrint("Firebase initialized successfully ✅");
  } catch (e) {
    debugPrint("Firebase initialization note: $e (Setup google-services.json for native FCM)");
  }
  runApp(const DuoChatApp());
}