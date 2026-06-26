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
        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Looking up water rights…'),
            if (showingMessage) ...[
              SizedBox(height: 16),
              Text(
                'This is taking longer than expected ',
                textAlign: TextAlign.center,
              ),
              Text('We are still searching...'),
              SizedBox(height: 8),
              Text('Please be patient,'),
              Text('as we are limited by the state database.'),
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
