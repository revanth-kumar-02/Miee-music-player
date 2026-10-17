import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/search/data/search_repository.dart';

void main() {
  test('Live search for West Coast returns deduplicated canonical results', () async {
    final repo = SearchRepository();
    final results = await repo.searchYouTube('West Coast');

    print('=== LIVE SEARCH RESULTS FOR "West Coast" ===');
    print('Total deduplicated results: ${results.length}');
    for (var i = 0; i < results.length && i < 15; i++) {
      final v = results[i];
      print('${i + 1}. [${v.id}] "${v.title}" by "${v.channelTitle}" (${v.duration}, ${v.viewCount})');
    }

    expect(results, isNotEmpty);

    // Verify there is AT MOST ONE canonical "West Coast" by Lana Del Rey in the standard recording
    final ldrWestCoastStandard = results.where((v) {
      final t = v.title.toLowerCase();
      final a = v.channelTitle.toLowerCase();
      return (t == 'west coast' || t.contains('west coast')) &&
          (a.contains('lana del rey') || a.contains('lanadelrey')) &&
          !t.contains('live') &&
          !t.contains('remix') &&
          !t.contains('cover') &&
          !t.contains('sped up') &&
          !t.contains('slowed');
    }).toList();

    print('Lana Del Rey West Coast standard tracks returned: ${ldrWestCoastStandard.length}');
    for (final track in ldrWestCoastStandard) {
      print('  -> [${track.id}] title: "${track.title}" | rawTitle: "${track.rawTitle}" | channel: "${track.channelTitle}" | rawChannel: "${track.rawChannelTitle}"');
    }

    // Must be exactly 1 canonical representative!
    expect(ldrWestCoastStandard.length, 1);
  });
}
