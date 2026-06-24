import 'package:flutter/material.dart';

// Placeholder — saved lookups will wire into Firebase in a future pass
class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Lookups')),
      body: const Center(
        child: Text('Saved lookups coming soon', style: TextStyle(color: Colors.grey)),
      ),
    );
  }
}
