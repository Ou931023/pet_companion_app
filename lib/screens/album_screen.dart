import 'package:flutter/material.dart';

import '../routes/app_routes.dart';

class AlbumScreen extends StatelessWidget {
  const AlbumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('照片相簿')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            '照片相簿',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const Text(
            '可以從這裡選一張喜歡的照片，陪寵物一起玩拼圖。',
            style: TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pushNamed(AppRoute.puzzle),
            icon: const Icon(Icons.photo_library),
            label: const Text('選照片玩拼圖'),
          ),
        ],
      ),
    );
  }
}
