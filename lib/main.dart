import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:prior/core/purchases_service.dart';
import 'package:prior/core/router.dart';
import 'package:prior/core/theme.dart';
import 'package:prior/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initPurchases();
  MapboxOptions.setAccessToken(
    'pk.eyJ1Ijoia3lkYXYiLCJhIjoiY21xcjNid29sMGtwMzJxcHd2czd6NmQ5aSJ9.NnCfgYoj6EK8Wg9E_dJXGg',
  );
  runApp(const ProviderScope(child: PriorApp()));
}

class PriorApp extends StatelessWidget {
  const PriorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Prior',
      theme: priorTheme,
      routerConfig: router,
    );
  }
}
