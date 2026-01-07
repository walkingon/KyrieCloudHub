import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
  }

  Future<void> _initPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = packageInfo.version;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于'), centerTitle: true),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              _buildAppIcon(colorScheme),
              const SizedBox(height: 20),
              _buildAppTitle(colorScheme),
              if (_version.isNotEmpty) _buildVersionBadge(colorScheme),
              const SizedBox(height: 32),
              _buildDescriptionCard(),
              const SizedBox(height: 24),
              _buildLinksSection(colorScheme),
              const SizedBox(height: 32),
              _buildCopyrightSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppIcon(ColorScheme colorScheme) {
    return Image.asset(
      'assets/images/ic_launcher.png',
      width: 96,
      height: 96,
    );
  }

  Widget _buildAppTitle(ColorScheme colorScheme) {
    return Text(
      'KyrieCloudHub',
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildVersionBadge(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'v$_version',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _buildDescriptionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Text(
            '跨平台云盘管理客户端，支持腾讯云 COS 和阿里云 OSS 对象存储服务。',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLinksSection(ColorScheme colorScheme) {
    final links = [
      {
        'icon': Icons.code,
        'title': '源代码',
        'url': 'https://github.com/walkingon/KyrieCloudHub',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            '相关链接',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ...links.map((link) => _buildLinkItem(link, colorScheme)),
      ],
    );
  }

  Widget _buildLinkItem(Map<String, dynamic> link, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => launchUrl(Uri.parse(link['url'])),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                link['icon'] as IconData,
                size: 22,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  link['title'] as String,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCopyrightSection() {
    return Column(
      children: [
        const SizedBox(height: 16),
        Text(
          'Copyright © 2026 walkingon',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => launchUrl(
            Uri.parse(
              'https://github.com/walkingon/KyrieCloudHub/blob/main/LICENSE',
            ),
          ),
          borderRadius: BorderRadius.circular(4),
          child: Text(
            'Apache License 2.0',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              decoration: TextDecoration.underline,
              decorationColor: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}
