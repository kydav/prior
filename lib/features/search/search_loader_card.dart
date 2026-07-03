import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prior/core/parcel_layer.dart';
import 'package:prior/core/water_rights_client.dart';

class SearchLoaderCard extends StatefulWidget {
  const SearchLoaderCard({super.key});

  @override
  State<SearchLoaderCard> createState() => _SearchLoaderCardState();
}

class _SearchLoaderCardState extends State<SearchLoaderCard> {
  late final Timer _timer;
  bool showingMessage = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 20), () {
      if (!mounted || showingMessage) return;
      setState(() {
        showingMessage = true;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Looking up water rights…'),
            if (showingMessage) ...[
              const SizedBox(height: 16),
              const Text(
                'This is taking longer than expected ',
                textAlign: TextAlign.center,
              ),
              const Text('We are still searching...'),
              const SizedBox(height: 8),
              const Text('Please be patient,'),
              const Text('as we are limited by the state database.'),
              TextButton(
                onPressed: () {
                  ParcelLayer.cancelFetch();
                  WaterRightsClient.instance.cancelColoradoLookup();
                },
                child: const Text('Cancel'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
