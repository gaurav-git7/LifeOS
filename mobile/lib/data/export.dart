// "Export everything": all your data as JSON (from the server) plus a readable
// Markdown file of your journal, handed to Android's share sheet.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'api/api_client.dart';
import 'stores.dart';

/// Returns an error message, or null when the share sheet opened.
Future<String?> exportEverything(WidgetRef ref) async {
  final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final dir = await getTemporaryDirectory();
  final files = <XFile>[];

  if (ref.read(authProvider).live) {
    try {
      final data = await ref.read(apiClientProvider).get<Map<String, dynamic>>('/users/me/export');
      final f = File('${dir.path}/lifeos-export-$stamp.json');
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      files.add(XFile(f.path, mimeType: 'application/json'));
    } on ApiException catch (e) {
      return e.message;
    }
  }

  final entries = [...ref.read(journalProvider).entries]..sort((a, b) => a.day.compareTo(b.day));
  if (entries.isNotEmpty) {
    final md = StringBuffer('# Journal\n');
    final fmt = DateFormat('EEEE, d MMMM yyyy');
    for (final e in entries) {
      md
        ..writeln()
        ..writeln('## ${fmt.format(e.day)}${e.title != null && e.title!.isNotEmpty ? ' · ${e.title}' : ''}')
        ..writeln()
        ..writeln(e.content.trim());
    }
    final f = File('${dir.path}/lifeos-journal-$stamp.md');
    await f.writeAsString(md.toString());
    files.add(XFile(f.path, mimeType: 'text/markdown'));
  }

  if (files.isEmpty) return 'Nothing to export yet.';
  await SharePlus.instance.share(ShareParams(files: files, subject: 'LifeOS export $stamp'));
  return null;
}
