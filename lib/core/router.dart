import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:prior/features/auth/login_screen.dart';
import 'package:prior/features/search/search_screen.dart';
import 'package:prior/features/detail/detail_screen.dart';
import 'package:prior/features/saved/saved_screen.dart';
import 'package:prior/data/water_right.dart';

final router = GoRouter(
  redirect: (_, state) {
    final authed = FirebaseAuth.instance.currentUser != null;
    if (!authed && state.matchedLocation != '/login') return '/login';
    if (authed && state.matchedLocation == '/login') return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    GoRoute(path: '/', builder: (_, _) => const SearchScreen()),
    GoRoute(
      path: '/detail',
      builder: (_, state) {
        final rights = state.extra as List<WaterRight>;
        return DetailScreen(rights: rights);
      },
    ),
    GoRoute(path: '/saved', builder: (_, _) => const SavedScreen()),
  ],
);
