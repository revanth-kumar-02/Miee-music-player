import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/itunes_metadata_service.dart';

/// Global provider for the singleton [ItunesMetadataService] instance.
final itunesMetadataServiceProvider = Provider<ItunesMetadataService>((ref) {
  return ItunesMetadataService();
});

