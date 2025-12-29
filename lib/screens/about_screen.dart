import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('关于')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 20),
            Icon(Icons.cloud, size: 64, color: Theme.of(context).primaryColor),
            SizedBox(height: 20),
            Text(
              'KyrieCloudHub',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text('Copyright [2025] [walkingon]'),
            SizedBox(height: 20),
            InkWell(
              onTap: () => launchUrl(
                Uri.parse('https://github.com/walkingon/KyrieCloudHub'),
              ),
              child: Text(
                'GitHub: https://github.com/walkingon/KyrieCloudHub',
                style: TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
