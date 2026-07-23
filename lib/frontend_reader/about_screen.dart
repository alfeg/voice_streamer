import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const String _repo = 'alfeg/voice_streamer';
  static const String _channelUrl = 'https://t.me/belgorodDroneLiveStream';
  static const String _releasesUrl =
      'https://github.com/alfeg/voice_streamer/releases';

  String _version = '';
  String _updateStatus = 'Проверка обновлений…';
  bool _updateAvailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
    await _checkUpdate(info.version);
  }

  Future<void> _checkUpdate(String current) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
      );
      req.headers.set(HttpHeaders.userAgentHeader, 'MaxReader');
      final resp = await req.close();
      if (resp.statusCode != 200) {
        if (mounted) setState(() => _updateStatus = 'Не удалось проверить');
        return;
      }
      final body = await resp.transform(utf8.decoder).join();
      final tag = (jsonDecode(body) as Map)['tag_name']?.toString() ?? '';
      final latest = tag.startsWith('v') ? tag.substring(1) : tag;
      if (!mounted) return;
      if (latest.isNotEmpty && latest != current) {
        setState(() {
          _updateAvailable = true;
          _updateStatus = 'Доступна новая версия: $tag';
        });
      } else {
        setState(() => _updateStatus = 'Установлена последняя версия');
      }
    } catch (_) {
      if (mounted) setState(() => _updateStatus = 'Не удалось проверить');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('О программе')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                Icon(Icons.record_voice_over, size: 56, color: cs.primary),
                const SizedBox(height: 8),
                const Text(
                  'MaxReader',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                Text(
                  _version.isEmpty ? '' : 'Версия $_version',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.campaign),
            title: const Text('Канал'),
            subtitle: const Text('t.me/belgorodDroneLiveStream'),
            onTap: () => _open(_channelUrl),
          ),
          ListTile(
            leading: Icon(
              _updateAvailable ? Icons.system_update : Icons.verified,
              color: _updateAvailable ? cs.primary : null,
            ),
            title: const Text('GitHub / релизы'),
            subtitle: Text(_updateStatus),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _open(_releasesUrl),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Лицензии библиотек'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'MaxReader',
              applicationVersion: _version,
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              'MaxReader — урезанный форк клиента Komet для озвучки каналов MAX. '
              'Не связан с MAX или VK. Синтез речи — offline (Piper / sherpa-onnx).',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
