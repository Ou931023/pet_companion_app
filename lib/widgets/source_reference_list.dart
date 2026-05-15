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
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 6),
          if (sources.isEmpty)
            const Text(
              '目前沒有取得可靠來源，我先不亂說，我可以先陪你聊聊或稍後再幫你查。',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            )
          else
            for (var i = 0; i < sources.length; i++)
              _SourceRow(index: i + 1, source: sources[i]),
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
    final date = source.publishedAt?.trim();
    final summary = source.summary.trim();
    return InkWell(
      onTap: () => _open(source.url),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$index. ', style: const TextStyle(fontSize: 13)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$siteName｜${source.title}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.indigo,
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
                  if (date != null && date.isNotEmpty)
                    Text(
                      '發布日期：$date',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),
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
