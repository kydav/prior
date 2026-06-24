// PLACEHOLDER — run `flutterfire configure --project=prior-water-rights`
// to replace this file with real values.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web not supported');
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('Platform not supported');
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCA0jV6eB-u7yLiGgdwV9CzQimvRx5mS54',
    appId: '1:254436903650:ios:d2ecfb3fd3ec8d083aecbb',
    messagingSenderId: '254436903650',
    projectId: 'prior-water-rights',
    storageBucket: 'prior-water-rights.firebasestorage.app',
    iosBundleId: 'com.auaha.prior',
  );

  // Replace with values from: flutterfire configure --project=prior-water-rights

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDDestLJV0-r01L4tnCPS45RynnwTus5rU',
    appId: '1:254436903650:android:ff58fca0946b6fd73aecbb',
    messagingSenderId: '254436903650',
    projectId: 'prior-water-rights',
    storageBucket: 'prior-water-rights.firebasestorage.app',
  );

}