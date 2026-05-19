import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/source_reference.dart';

class SourceReferenceList extends StatelessWidget {
  const SourceReferenceList({
    super.key,
    required this.sources,
  });

  final List<SourceReference> sources;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();
    final visibleSources = sources.take(2).toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '資料來源：',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < visibleSources.length; i++)
            _SourceRow(index: i + 1, source: visibleSources[i]),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.index,
    required this.source,
  });

  final int index;
  final SourceReference source;

  @override
  Widget build(BuildContext context) {
    final siteName = source.siteName.isEmpty ? '來源網站' : source.siteName;
    final summary = source.summary.trim();
    return InkWell(
      onTap: () => _open(source.url),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$index.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.indigo,
                    ),
                  ),
                  Text(
                    siteName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      height: 1.25,
                    ),
                  ),
                  if (summary.isNotEmpty)
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        height: 1.25,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.open_in_new, size: 15, color: Colors.indigo),
          ],
        ),
      ),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
