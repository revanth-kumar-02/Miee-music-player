import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../domain/artist_model.dart';

/// Verified album entity for an artist from Deezer or local metadata.
class ArtistAlbum {
  final String id;
  final String title;
  final String coverUrl;
  final String releaseDate;
  final int trackCount;
  final String artistName;

  const ArtistAlbum({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.releaseDate,
    this.trackCount = 0,
    this.artistName = '',
  });

  factory ArtistAlbum.fromDeezer(Map<String, dynamic> json, {String artistName = ''}) {
    final artist = json['artist'] as Map<String, dynamic>? ?? {};
    final resolvedArtistName = (artist['name'] as String?) ?? artistName;
    return ArtistAlbum(
      id: (json['id'] ?? '').toString(),
      title: json['title'] as String? ?? 'Unknown Album',
      coverUrl: json['cover_xl'] as String? ??
          json['cover_big'] as String? ??
          json['cover_medium'] as String? ??
          json['cover'] as String? ?? '',
      releaseDate: json['release_date'] as String? ?? '',
      trackCount: json['nb_tracks'] as int? ?? 0,
      artistName: resolvedArtistName,
    );
  }
}

/// Verified top track for an artist from Deezer metadata.
class ArtistTopTrack {
  final String id;
  final String title;
  final String artistName;
  final int durationSeconds;
  final String albumCover;
  final String albumTitle;

  const ArtistTopTrack({
    required this.id,
    required this.title,
    required this.artistName,
    required this.durationSeconds,
    required this.albumCover,
    required this.albumTitle,
  });

  factory ArtistTopTrack.fromDeezer(Map<String, dynamic> json) {
    final album = json['album'] as Map<String, dynamic>? ?? {};
    final artist = json['artist'] as Map<String, dynamic>? ?? {};
    return ArtistTopTrack(
      id: (json['id'] ?? '').toString(),
      title: json['title'] as String? ?? '',
      artistName: artist['name'] as String? ?? '',
      durationSeconds: json['duration'] as int? ?? 0,
      albumCover: album['cover_xl'] as String? ??
          album['cover_big'] as String? ??
          album['cover_medium'] as String? ?? '',
      albumTitle: album['title'] as String? ?? '',
    );
  }

  String get durationString {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

abstract class ArtistRepository {
  Future<List<ArtistModel>> getPopularArtists({String? language});
  Future<List<ArtistModel>> searchArtists(String query, {String? language});
  Future<List<ArtistModel>> getRelatedArtists(String artistId);
  Future<ArtistModel?> getArtistDetails(String artistId);
  Future<List<ArtistAlbum>> getArtistAlbums(String artistId);
  Future<List<ArtistTopTrack>> getArtistTopTracks(String artistId);
  List<String> getSupportedLanguages();
}

class DeezerArtistRepository implements ArtistRepository {
  final HttpClient? _client = kIsWeb ? null : HttpClient();
  final Map<String, List<ArtistModel>> _searchCache = {};
  final Map<String, List<ArtistModel>> _relatedCache = {};
  final Map<String, ArtistModel> _artistDetailsCache = {};
  final Map<String, List<ArtistAlbum>> _albumsCache = {};
  final Map<String, List<ArtistTopTrack>> _topTracksCache = {};

  DeezerArtistRepository() {
    if (!kIsWeb) {
      _client?.connectionTimeout = const Duration(seconds: 10);
    }
  }

  static const List<String> _languages = [
    'All',
    'Tamil',
    'Hindi',
    'Telugu',
    'Malayalam',
    'Kannada',
    'English',
  ];

  @override
  List<String> getSupportedLanguages() => _languages;

  List<ArtistModel> get curatedArtists => _curatedArtists;
  static List<ArtistModel> get staticCuratedArtists => _curatedArtists;

  /// Curated selection of top artists with verified Deezer IDs, active CDN images,
  /// and verified language tags across Indian and International music.
  static const List<ArtistModel> _curatedArtists = [
    // ── Tamil Artists ───────────────────────────────────────────────────────────
    ArtistModel(
      id: '491',
      name: 'A. R. Rahman',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/bd34315ef977a62a9e28c1ab19bb8ac4/500x500-000000-80-0-0.jpg',
      fanCount: 284432,
      languages: ['Tamil', 'Hindi', 'Telugu'],
    ),
    ArtistModel(
      id: '1516162',
      name: 'Anirudh Ravichander',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/9da0a547b39e99bc35c6a9724aef91bf/500x500-000000-80-0-0.jpg',
      fanCount: 53583,
      languages: ['Tamil', 'Telugu', 'Hindi'],
    ),
    ArtistModel(
      id: '101677',
      name: 'Ilaiyaraaja',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/aeeca2a4b9f808c8e8f5d281b1fb48d0/500x500-000000-80-0-0.jpg',
      fanCount: 13159,
      languages: ['Tamil', 'Telugu'],
    ),
    ArtistModel(
      id: '1216625',
      name: 'Sid Sriram',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/fbe3e1d17fc6958e047f011f74233f82/500x500-000000-80-0-0.jpg',
      fanCount: 18160,
      languages: ['Tamil', 'Telugu', 'Malayalam'],
    ),
    ArtistModel(
      id: '4325950',
      name: 'Santhosh Narayanan',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/74004fed94dddf9ae2d7c83084eaf1ad/500x500-000000-80-0-0.jpg',
      fanCount: 9529,
      languages: ['Tamil', 'Telugu'],
    ),
    ArtistModel(
      id: '3847661',
      name: 'Yuvan Shankar Raja',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/1dbf7d81a2e964d9c707e53478407974/500x500-000000-80-0-0.jpg',
      fanCount: 14686,
      languages: ['Tamil', 'Telugu'],
    ),
    ArtistModel(
      id: '362663',
      name: 'Harris Jayaraj',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/b10caf45eae518a2b16997874ded7143/500x500-000000-80-0-0.jpg',
      fanCount: 20723,
      languages: ['Tamil', 'Telugu'],
    ),
    ArtistModel(
      id: '6346288',
      name: 'Hiphop Tamizha',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/bc28fc5d771e2702dab60c447225fcaf/500x500-000000-80-0-0.jpg',
      fanCount: 21607,
      languages: ['Tamil', 'Telugu'],
    ),
    ArtistModel(
      id: '1528950',
      name: 'Vijay Antony',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/49a5afd37d3b385fb5f174cdeec46611/500x500-000000-80-0-0.jpg',
      fanCount: 6783,
      languages: ['Tamil', 'Telugu'],
    ),
    ArtistModel(
      id: '4102526',
      name: 'G. V. Prakash Kumar',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/4305ff5feb2f773006e9ab559a22063a/500x500-000000-80-0-0.jpg',
      fanCount: 15323,
      languages: ['Tamil', 'Telugu'],
    ),
    ArtistModel(
      id: '4513306',
      name: 'Pradeep Kumar',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/87c0266a02406bc9c500bd3620d1d52b/500x500-000000-80-0-0.jpg',
      fanCount: 1188,
      languages: ['Tamil', 'Telugu'],
    ),
    ArtistModel(
      id: '298792',
      name: 'D. Imman',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/b7f064e7e78b9bf3eb1ac62839c731cd/500x500-000000-80-0-0.jpg',
      fanCount: 12276,
      languages: ['Tamil'],
    ),
    ArtistModel(
      id: '98323',
      name: 'S. P. Balasubrahmanyam',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/7a91e898679cfff367e54d71a1f88f1a/500x500-000000-80-0-0.jpg',
      fanCount: 8648,
      languages: ['Tamil', 'Telugu', 'Hindi', 'Kannada', 'Malayalam'],
    ),
    ArtistModel(
      id: '1292235',
      name: 'Dhanush',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/876a47e9f312cd0111edb35dcdc477b4/500x500-000000-80-0-0.jpg',
      fanCount: 15180,
      languages: ['Tamil', 'Telugu', 'Hindi'],
    ),
    ArtistModel(
      id: '204414',
      name: 'Karthik',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/b13e79b8bdc0f6581d4489e406407c24/500x500-000000-80-0-0.jpg',
      fanCount: 9267,
      languages: ['Tamil', 'Telugu'],
    ),
    ArtistModel(
      id: '5124260',
      name: 'Jonita Gandhi',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/f756c825ab0eb367cd85f077c28d0719/500x500-000000-80-0-0.jpg',
      fanCount: 13709,
      languages: ['Tamil', 'Hindi', 'Telugu'],
    ),
    ArtistModel(
      id: '7023111',
      name: 'Dhee',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/011b57430ce0f654bf5deb01b70f365e/500x500-000000-80-0-0.jpg',
      fanCount: 2891,
      languages: ['Tamil', 'Telugu'],
    ),
    ArtistModel(
      id: '223843195',
      name: 'Sai Abhyankkar',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/234646e93d6ab2923f3bdc363f53d330/500x500-000000-80-0-0.jpg',
      fanCount: 4171,
      languages: ['Tamil'],
    ),
    ArtistModel(
      id: '51819712',
      name: 'Arivu',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/64eca1d25be44fa797e9390b6b7401b7/500x500-000000-80-0-0.jpg',
      fanCount: 2079,
      languages: ['Tamil'],
    ),
    ArtistModel(
      id: '185130477',
      name: 'Paal Dabba',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/14bd7723396257f9a25f24def93b3ff3/500x500-000000-80-0-0.jpg',
      fanCount: 435,
      languages: ['Tamil'],
    ),
    ArtistModel(
      id: '14407599',
      name: 'Stephen Zechariah',
      imageUrl: 'https://i.scdn.co/image/ab6761610000e5ebcb227b29758b87233f69e28a',
      fanCount: 962,
      languages: ['Tamil'],
    ),
    ArtistModel(
      id: '111714562',
      name: 'Asal Kolaar',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/313acd38066990de1684f2fd790e3904/500x500-000000-80-0-0.jpg',
      fanCount: 1036,
      languages: ['Tamil'],
    ),
    ArtistModel(
      id: '4054149',
      name: 'Sean Roldan',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/7df3f3636410c7e3572473b26a3158ce/500x500-000000-80-0-0.jpg',
      fanCount: 469,
      languages: ['Tamil'],
    ),
    ArtistModel(
      id: '7685852',
      name: 'Kaber Vasuki',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/8d4619f976440d230d1ae0878c4bb49d/500x500-000000-80-0-0.jpg',
      fanCount: 83,
      languages: ['Tamil'],
    ),
    ArtistModel(
      id: '9382312',
      name: 'Mugen Rao',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/7291f2c5394fb62f76daa1a40147b46a/500x500-000000-80-0-0.jpg',
      fanCount: 955,
      languages: ['Tamil'],
    ),
    ArtistModel(
      id: '6892911',
      name: 'A.D.K.',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/907402326f648caa5b0ef8f7f4ed8fec/500x500-000000-80-0-0.jpg',
      fanCount: 6,
      languages: ['Tamil'],
    ),
    ArtistModel(
      id: '14417043',
      name: 'ofRO',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/9d849f8968498717a2b37b3368cbdf81/500x500-000000-80-0-0.jpg',
      fanCount: 66,
      languages: ['Tamil'],
    ),
    ArtistModel(
      id: '594484',
      name: 'Sam C.S.',
      imageUrl: 'https://c.saavncdn.com/artists/Sam_C_S__001_20260904065259_500x500.jpg',
      fanCount: 25000,
      languages: ['Tamil'],
    ),
    ArtistModel(
      id: '5449618',
      name: 'Ghibran',
      imageUrl: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/9/9d/M_Ghibran_at_Theeran_Adhigaaram_Ondru_Press_Meet.jpg/500px-M_Ghibran_at_Theeran_Adhigaaram_Ondru_Press_Meet.jpg',
      fanCount: 1635,
      languages: ['Tamil'],
    ),

    // ── Hindi Artists ───────────────────────────────────────────────────────────
    ArtistModel(
      id: '3830821',
      name: 'Arijit Singh',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/ac5350cff290edd5b69fa584b8b1bd4f/500x500-000000-80-0-0.jpg',
      fanCount: 233394,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '98371',
      name: 'Shreya Ghoshal',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/3bb832d37d10ff2affcfa9afdc7c68a0/500x500-000000-80-0-0.jpg',
      fanCount: 256791,
      languages: ['Hindi', 'Tamil', 'Telugu', 'Malayalam', 'Kannada'],
    ),
    ArtistModel(
      id: '70075',
      name: 'Sonu Nigam',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/812220125c4f0db57050438b65afcf78/500x500-000000-80-0-0.jpg',
      fanCount: 166968,
      languages: ['Hindi', 'Kannada'],
    ),
    ArtistModel(
      id: '129846',
      name: 'Neha Kakkar',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/3a0f7ba65d6d8c1081b461ee49cb59e8/500x500-000000-80-0-0.jpg',
      fanCount: 74925,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '405736',
      name: 'Atif Aslam',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/0ea90444148fff9c11d77f06a344724e/500x500-000000-80-0-0.jpg',
      fanCount: 221388,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '69736',
      name: 'K.K.',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/e118eeb5332fe76610d4b355fdb61b03/500x500-000000-80-0-0.jpg',
      fanCount: 25838,
      languages: ['Hindi', 'Tamil', 'Telugu'],
    ),
    ArtistModel(
      id: '97141',
      name: 'Kishore Kumar',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/5972263348ad902e29a4749e748ff452/500x500-000000-80-0-0.jpg',
      fanCount: 36118,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '10587',
      name: 'Lata Mangeshkar',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/837d46f90f541736e07817f463317c80/500x500-000000-80-0-0.jpg',
      fanCount: 88383,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '290619',
      name: 'Pritam',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/d4914ccd414067cd5e2c108867079a85/500x500-000000-80-0-0.jpg',
      fanCount: 71431,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '8419888',
      name: 'Jubin Nautiyal',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/9031b483049b5551abcb11529873b4f6/500x500-000000-80-0-0.jpg',
      fanCount: 21691,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '6048770',
      name: 'Darshan Raval',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/9428424029a929927b7081b70d3a0fc6/500x500-000000-80-0-0.jpg',
      fanCount: 20931,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '5017623',
      name: 'Armaan Malik',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/3aacd4e00a34aefb6041d30e0cc5bc5e/500x500-000000-80-0-0.jpg',
      fanCount: 31008,
      languages: ['Hindi', 'Telugu', 'English'],
    ),
    ArtistModel(
      id: '1093616',
      name: 'Badshah',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/5b90b89299a7d42f81d79afa263a85d2/500x500-000000-80-0-0.jpg',
      fanCount: 76742,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '1199677',
      name: 'Diljit Dosanjh',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/79b85e695e0ca6529e56bf3b628e92bd/500x500-000000-80-0-0.jpg',
      fanCount: 46484,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '6555107',
      name: 'Karan Aujla',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/a91a1d5ea91e85e4f0966569b50e8d6a/500x500-000000-80-0-0.jpg',
      fanCount: 33316,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '76708242',
      name: 'AP Dhillon',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/52594ac9fa763dc163ed13d21cb130ec/500x500-000000-80-0-0.jpg',
      fanCount: 28764,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '12423322',
      name: 'Sidhu Moosewala',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/f559ebe3851db26a6a47a76b1d95748f/500x500-000000-80-0-0.jpg',
      fanCount: 37470,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '5208987',
      name: 'Prateek Kuhad',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/7f69b3905ae630b3f7bcd826bd2dc46f/500x500-000000-80-0-0.jpg',
      fanCount: 3460,
      languages: ['Hindi', 'English'],
    ),
    ArtistModel(
      id: '64116612',
      name: 'Anuv Jain',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/eb0c0e91c8ad621b41178e0d66c81057/500x500-000000-80-0-0.jpg',
      fanCount: 4351,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '14779',
      name: 'Sunidhi Chauhan',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/37dbd33ae8cf7075e247968acf4b48da/500x500-000000-80-0-0.jpg',
      fanCount: 99877,
      languages: ['Hindi', 'Tamil', 'Telugu'],
    ),
    ArtistModel(
      id: '136941',
      name: 'Mohit Chauhan',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/f9533880207ac5714b65e760e5686af8/500x500-000000-80-0-0.jpg',
      fanCount: 33272,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '5196512',
      name: 'Raftaar',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/29570d57452267a2a237c812e79fe8fe/500x500-000000-80-0-0.jpg',
      fanCount: 15855,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '13693077',
      name: 'KR\$NA',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/44dcd9d1d0be03a355c2d93c31bd8015/500x500-000000-80-0-0.jpg',
      fanCount: 1852,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '57267132',
      name: 'MC STAN',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/5a6fc1cf6fa0f4edadeebfaace93f612/500x500-000000-80-0-0.jpg',
      fanCount: 794,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '204661437',
      name: 'King',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/5758debe23bf3acf0ec0d657f46b9b6e/500x500-000000-80-0-0.jpg',
      fanCount: 1200,
      languages: ['Hindi'],
    ),
    ArtistModel(
      id: '5425304',
      name: 'Jasleen Royal',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/c83791c10f0ec33e1d8a18b1a8ff9f84/500x500-000000-80-0-0.jpg',
      fanCount: 1937,
      languages: ['Hindi', 'Punjabi'],
    ),
    ArtistModel(
      id: '1212166',
      name: 'Shilpa Rao',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/d6c9df2eb27416ade91b4b8d7caa1669/500x500-000000-80-0-0.jpg',
      fanCount: 5258,
      languages: ['Hindi', 'Tamil', 'Telugu'],
    ),

    // ── Telugu Artists ──────────────────────────────────────────────────────────
    ArtistModel(
      id: '247365',
      name: 'Devi Sri Prasad',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/a904f8ee6cc4dcb472f75bd8ae1a21da/500x500-000000-80-0-0.jpg',
      fanCount: 6462,
      languages: ['Telugu', 'Tamil'],
    ),
    ArtistModel(
      id: '1516104',
      name: 'S. Thaman',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/fe520c37ba48ea96638cf2f52f1bbc08/500x500-000000-80-0-0.jpg',
      fanCount: 3146,
      languages: ['Telugu', 'Tamil'],
    ),
    ArtistModel(
      id: '2145171',
      name: 'M. M. Keeravani',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/625024c20533d31f352a3585444ddf19/500x500-000000-80-0-0.jpg',
      fanCount: 297,
      languages: ['Telugu', 'Hindi', 'Tamil'],
    ),
    ArtistModel(
      id: '66381602',
      name: 'Ram Miriyala',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/43f399df39ffe548e7ed9b5495abf6e1/500x500-000000-80-0-0.jpg',
      fanCount: 75,
      languages: ['Telugu'],
    ),
    ArtistModel(
      id: '11577417',
      name: 'Anurag Kulkarni',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/f9f1f4491e7efc579dff25792bbc0fd6/500x500-000000-80-0-0.jpg',
      fanCount: 163,
      languages: ['Telugu'],
    ),
    ArtistModel(
      id: '13450407',
      name: 'Mangli',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/1c8da61b7b08d8b82cba95671156dfc8/500x500-000000-80-0-0.jpg',
      fanCount: 80,
      languages: ['Telugu'],
    ),
    ArtistModel(
      id: '4660615',
      name: 'Rahul Sipligunj',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/48d836b87112575da37fce168cb6735f/500x500-000000-80-0-0.jpg',
      fanCount: 148,
      languages: ['Telugu'],
    ),
    ArtistModel(
      id: '9129552',
      name: 'Vivek Sagar',
      imageUrl: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/9/94/Vivek_Sagar.jpg/500px-Vivek_Sagar.jpg',
      fanCount: 43,
      languages: ['Telugu'],
    ),
    ArtistModel(
      id: '4333864',
      name: 'Mickey J. Meyer',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/1edd27e762624f8a0a16fe79238eee4c/500x500-000000-80-0-0.jpg',
      fanCount: 94,
      languages: ['Telugu'],
    ),
    ArtistModel(
      id: '7325920',
      name: 'Bheems Ceciroleo',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/b0901b18c94bef9ae4a07488dc7270c8/500x500-000000-80-0-0.jpg',
      fanCount: 42,
      languages: ['Telugu'],
    ),
    ArtistModel(
      id: '1215220',
      name: 'Haricharan',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/923607e2ef5b425a8c6203f7439ad44f/500x500-000000-80-0-0.jpg',
      fanCount: 4700,
      languages: ['Telugu', 'Tamil'],
    ),
    ArtistModel(
      id: '1632155',
      name: 'Sunitha',
      imageUrl: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/0/04/Sunitha_film_fare.jpg/500px-Sunitha_film_fare.jpg',
      fanCount: 80,
      languages: ['Telugu'],
    ),
    ArtistModel(
      id: '541067',
      name: 'Geetha Madhuri',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/c0b08d219cdaadbeccd644fda9160e11/500x500-000000-80-0-0.jpg',
      fanCount: 1713,
      languages: ['Telugu'],
    ),

    // ── Malayalam Artists ───────────────────────────────────────────────────────
    ArtistModel(
      id: '5570139',
      name: 'Sushin Shyam',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/6ba914ca28d2c5cc21dc3effa07c690d/500x500-000000-80-0-0.jpg',
      fanCount: 1677,
      languages: ['Malayalam'],
    ),
    ArtistModel(
      id: '5588729',
      name: 'Hesham Abdul Wahab',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/567c9aaa183caf6d18b33025343a014b/500x500-000000-80-0-0.jpg',
      fanCount: 475,
      languages: ['Malayalam', 'Telugu'],
    ),
    ArtistModel(
      id: '1323288',
      name: 'Jakes Bejoy',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/cba5a594962a9850946e394fefb73698/500x500-000000-80-0-0.jpg',
      fanCount: 758,
      languages: ['Malayalam', 'Tamil', 'Telugu'],
    ),
    ArtistModel(
      id: '4121191',
      name: 'Gopi Sundar',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/19b39210981ab9185024453d8ddbda07/500x500-000000-80-0-0.jpg',
      fanCount: 736,
      languages: ['Malayalam', 'Telugu', 'Tamil'],
    ),
    ArtistModel(
      id: '100151882',
      name: 'Dabzee',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/e03dadf32867ef746c362fc0d9235774/500x500-000000-80-0-0.jpg',
      fanCount: 1213,
      languages: ['Malayalam'],
    ),
    ArtistModel(
      id: '63097132',
      name: 'HanuMankind',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/7d46dbee1e5599894c72aebd8148d97d/500x500-000000-80-0-0.jpg',
      fanCount: 6928,
      languages: ['English', 'Malayalam'],
    ),
    ArtistModel(
      id: '6842847',
      name: 'Sithara Krishnakumar',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/80503e0cc5c010dc6dc44f0e20f451a7/500x500-000000-80-0-0.jpg',
      fanCount: 411,
      languages: ['Malayalam', 'Tamil'],
    ),
    ArtistModel(
      id: '1471591',
      name: 'Job Kurian',
      imageUrl: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/42/Job_Kurian.jpg/500px-Job_Kurian.jpg',
      fanCount: 326,
      languages: ['Malayalam'],
    ),
    ArtistModel(
      id: '101832',
      name: 'K. J. Yesudas',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/b42a9228338e4e3792e51bcad5e14cb9/500x500-000000-80-0-0.jpg',
      fanCount: 7720,
      languages: ['Malayalam', 'Tamil', 'Telugu', 'Kannada', 'Hindi'],
    ),
    ArtistModel(
      id: '1601573',
      name: 'K. S. Chithra',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/be49097501022690d1dce5b9d3c864e4/500x500-000000-80-0-0.jpg',
      fanCount: 7643,
      languages: ['Malayalam', 'Tamil', 'Telugu', 'Kannada', 'Hindi'],
    ),

    // ── Kannada Artists ─────────────────────────────────────────────────────────
    ArtistModel(
      id: '5893727',
      name: 'Ravi Basrur',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/8cd91105aa78393cbddd3e7215e2eb55/500x500-000000-80-0-0.jpg',
      fanCount: 248,
      languages: ['Kannada', 'Telugu', 'Tamil', 'Hindi'],
    ),
    ArtistModel(
      id: '10016766',
      name: 'B. Ajaneesh Loknath',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/a3319b808420e0f22cbf857a17e4b8f1/500x500-000000-80-0-0.jpg',
      fanCount: 71,
      languages: ['Kannada', 'Tamil', 'Telugu'],
    ),
    ArtistModel(
      id: '5529440',
      name: 'Charan Raj',
      imageUrl: 'https://upload.wikimedia.org/wikipedia/en/4/48/Charan_Raj_composer.jpeg',
      fanCount: 23,
      languages: ['Kannada'],
    ),
    ArtistModel(
      id: '463801',
      name: 'Arjun Janya',
      imageUrl: 'https://c.saavncdn.com/artists/Arjun_Janya_004_20230327131756_500x500.jpg',
      fanCount: 165,
      languages: ['Kannada'],
    ),
    ArtistModel(
      id: '685920',
      name: 'Vasuki Vaibhav',
      imageUrl: 'https://c.saavncdn.com/artists/Vasuki_Vaibhav_002_20200731124945_500x500.jpg',
      fanCount: 33,
      languages: ['Kannada'],
    ),
    ArtistModel(
      id: '5835476',
      name: 'Chandan Shetty',
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/e/e7/Chandan_Shetty_%281%29.jpg',
      fanCount: 130,
      languages: ['Kannada'],
    ),
    ArtistModel(
      id: '127529',
      name: 'Vijay Prakash',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/3d112cbc8570a026002b7e05142dc191/500x500-000000-80-0-0.jpg',
      fanCount: 3732,
      languages: ['Kannada', 'Tamil', 'Telugu', 'Hindi'],
    ),
    ArtistModel(
      id: '12669135',
      name: 'Sanjith Hegde',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/d134d28ca5af4c7fd176f1ae5188c667/500x500-000000-80-0-0.jpg',
      fanCount: 193,
      languages: ['Kannada', 'Tamil', 'Telugu'],
    ),
    ArtistModel(
      id: '117166',
      name: 'Raghu Dixit',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/12e8853ad9bffbc713f08eef12c95f38/500x500-000000-80-0-0.jpg',
      fanCount: 406,
      languages: ['Kannada', 'Hindi'],
    ),

    // ── English / International Artists ─────────────────────────────────────────
    ArtistModel(
      id: '12246',
      name: 'Taylor Swift',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/cc2495870fe1a792ad0cdb05501ad5ec/500x500-000000-80-0-0.jpg',
      fanCount: 12749185,
      languages: ['English'],
    ),
    ArtistModel(
      id: '4050205',
      name: 'The Weeknd',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/581693b4724a7fcfa754455101e13a44/500x500-000000-80-0-0.jpg',
      fanCount: 14738703,
      languages: ['English'],
    ),
    ArtistModel(
      id: '4495513',
      name: 'Travis Scott',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/8d8316146026d7e6ce377e314536df62/500x500-000000-80-0-0.jpg',
      fanCount: 3149741,
      languages: ['English'],
    ),
    ArtistModel(
      id: '7543848',
      name: 'Post Malone',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/a5a8cca44e7eab2db7d44e039bed2574/500x500-000000-80-0-0.jpg',
      fanCount: 4209854,
      languages: ['English'],
    ),
    ArtistModel(
      id: '288166',
      name: 'Justin Bieber',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/fe097f693cebf1f882e3da79e99e3bf9/500x500-000000-80-0-0.jpg',
      fanCount: 11170350,
      languages: ['English'],
    ),
    ArtistModel(
      id: '11152580',
      name: 'Olivia Rodrigo',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/2c9e480317183c037eaebcd7ba96daf4/500x500-000000-80-0-0.jpg',
      fanCount: 1838026,
      languages: ['English'],
    ),
    ArtistModel(
      id: '5313805',
      name: 'Harry Styles',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/1151dba9b3edc0633adf35b64c21713f/500x500-000000-80-0-0.jpg',
      fanCount: 2204419,
      languages: ['English'],
    ),
    ArtistModel(
      id: '5531258',
      name: 'SZA',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/8ced041da2bed70d5715f0860956169b/500x500-000000-80-0-0.jpg',
      fanCount: 1337482,
      languages: ['English'],
    ),
    ArtistModel(
      id: '1562681',
      name: 'Ariana Grande',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/721d8fab84b315502de422b8d0901509/500x500-000000-80-0-0.jpg',
      fanCount: 13446087,
      languages: ['English'],
    ),
    ArtistModel(
      id: '75798',
      name: 'Adele',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/e5fc443d2abc03b487234ba4de65a001/500x500-000000-80-0-0.jpg',
      fanCount: 15494705,
      languages: ['English'],
    ),
    ArtistModel(
      id: '145',
      name: 'Beyoncé',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/0aa9d669be4e7310b8647afae37ffaab/500x500-000000-80-0-0.jpg',
      fanCount: 12854188,
      languages: ['English'],
    ),
    ArtistModel(
      id: '564',
      name: 'Rihanna',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/b78cdc205fae2641b89208e78b30e1b3/500x500-000000-80-0-0.jpg',
      fanCount: 18106631,
      languages: ['English'],
    ),
    ArtistModel(
      id: '647650',
      name: 'Twenty One Pilots',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/2e6d4d494a7b7b2c4bea2ccefad368f5/500x500-000000-80-0-0.jpg',
      fanCount: 5010400,
      languages: ['English'],
    ),
    ArtistModel(
      id: '27',
      name: 'Daft Punk',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/638e69b9caaf9f9f3f8826febea7b543/500x500-000000-80-0-0.jpg',
      fanCount: 5221474,
      languages: ['English'],
    ),
    ArtistModel(
      id: '892',
      name: 'Coldplay',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/3087954bca22f306324912e5ac8375c3/500x500-000000-80-0-0.jpg',
      fanCount: 18420048,
      languages: ['English'],
    ),
    ArtistModel(
      id: '9635624',
      name: 'Billie Eilish',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/8eab1a9a644889aabaca1e193e05f984/500x500-000000-80-0-0.jpg',
      fanCount: 9276075,
      languages: ['English'],
    ),
    ArtistModel(
      id: '13',
      name: 'Eminem',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/0f30bbd33a680030054af004d698d6ac/500x500-000000-80-0-0.jpg',
      fanCount: 19143033,
      languages: ['English'],
    ),
    ArtistModel(
      id: '1424821',
      name: 'Lana Del Rey',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/8994d3be1a59a72f887f1f8afd2d4c6c/500x500-000000-80-0-0.jpg',
      fanCount: 5824851,
      languages: ['English'],
    ),
    ArtistModel(
      id: '8706544',
      name: 'Dua Lipa',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/877872aaf75694f11d53c318700ab2b5/500x500-000000-80-0-0.jpg',
      fanCount: 8794545,
      languages: ['English'],
    ),
    ArtistModel(
      id: '384236',
      name: 'Ed Sheeran',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/d6bb84390641d8ae9118228d9544e53d/500x500-000000-80-0-0.jpg',
      fanCount: 20936274,
      languages: ['English'],
    ),
    ArtistModel(
      id: '525046',
      name: 'Kendrick Lamar',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/be0a7c550567f4af0ed202d7235b74d6/500x500-000000-80-0-0.jpg',
      fanCount: 6186041,
      languages: ['English'],
    ),
    ArtistModel(
      id: '416239',
      name: 'Imagine Dragons',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/1ba025c23cae3dee14b51152990285fc/500x500-000000-80-0-0.jpg',
      fanCount: 9544700,
      languages: ['English'],
    ),
    ArtistModel(
      id: '1182',
      name: 'Arctic Monkeys',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/6c03e4c7c36800897fd468633286db24/500x500-000000-80-0-0.jpg',
      fanCount: 4969820,
      languages: ['English'],
    ),
    ArtistModel(
      id: '412',
      name: 'Queen',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/71eeb9e2eeb375df35a3c0654a5a01ab/500x500-000000-80-0-0.jpg',
      fanCount: 12833874,
      languages: ['English'],
    ),
    ArtistModel(
      id: '246791',
      name: 'Drake',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/eb0ed5b21d1ea5af021fc074ded0e91f/500x500-000000-80-0-0.jpg',
      fanCount: 24107809,
      languages: ['English'],
    ),
    ArtistModel(
      id: '429675',
      name: 'Bruno Mars',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/90f0b5b11df4f87ee878f38569b5995b/500x500-000000-80-0-0.jpg',
      fanCount: 12823185,
      languages: ['English'],
    ),
  ];

  @override
  Future<List<ArtistModel>> getPopularArtists({String? language}) async {
    final lang = language?.trim() ?? 'All';
    if (lang.isEmpty || lang.toLowerCase() == 'all') {
      return _curatedArtists;
    }
    return _curatedArtists.where((a) => a.matchesLanguage(lang)).toList();
  }

  @override
  Future<List<ArtistModel>> searchArtists(String query, {String? language}) async {
    final cleanQuery = query.trim();
    final lang = language?.trim() ?? 'All';
    final hasLangFilter = lang.isNotEmpty && lang.toLowerCase() != 'all';

    if (cleanQuery.isEmpty) {
      return getPopularArtists(language: language);
    }

    final cacheKey = '${lang.toLowerCase()}_${cleanQuery.toLowerCase()}';
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    // 1. Check local catalog first for instant, verified high-resolution matches
    final normClean = cleanQuery.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final collapsedClean = normClean.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);

    final localMatches = _curatedArtists.where((artist) {
      final nameLower = artist.name.toLowerCase();
      final directMatch = nameLower.contains(cleanQuery.toLowerCase());

      final normArtist = nameLower.replaceAll(RegExp(r'[^a-z0-9]'), '');
      final collapsedArtist = normArtist.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);

      final punctuationMatch = (normArtist == normClean) ||
          (normClean.length >= 3 &&
              (normArtist.contains(normClean) ||
                  (normArtist.length >= 4 && normClean.contains(normArtist))));

      final spellingVariationMatch = (collapsedArtist == collapsedClean && collapsedClean.length >= 2) ||
          (collapsedClean.length >= 3 &&
              (collapsedArtist.contains(collapsedClean) ||
                  (collapsedArtist.length >= 4 && collapsedClean.contains(collapsedArtist))));

      if (!directMatch && !punctuationMatch && !spellingVariationMatch) return false;
      if (hasLangFilter) {
        return artist.matchesLanguage(lang);
      }
      return true;
    }).toList();

    // 2. Fetch live results from Deezer API to support any artist in the world
    if (kIsWeb || _client == null) {
      return localMatches;
    }

    try {
      final uri = Uri.parse(
        'https://api.deezer.com/search/artist?q=${Uri.encodeQueryComponent(cleanQuery)}&limit=15',
      );
      final req = await _client!.getUrl(uri);
      final resp = await req.close();

      if (resp.statusCode != 200) {
        return localMatches;
      }

      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final items = json['data'] as List<dynamic>? ?? [];

      final remoteArtists = items
          .map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            final rawName = map['name'] as String? ?? '';
            // Check if matches curated artist to inherit verified picture and language tags
            final curatedMatch = _curatedArtists.where(
              (c) => c.name.toLowerCase() == rawName.toLowerCase() || c.id == (map['id'] ?? '').toString(),
            ).firstOrNull;

            if (curatedMatch != null) {
              return curatedMatch;
            }

            return ArtistModel.fromDeezer(map);
          })
          .where((a) => a.name.isNotEmpty && a.id.isNotEmpty)
          .toList();

      // Merge local matches and remote matches without duplicates
      final seenIds = <String>{};
      final combined = <ArtistModel>[];

      for (final a in [...localMatches, ...remoteArtists]) {
        if (seenIds.add(a.id)) {
          combined.add(a);
        }
      }

      if (combined.isNotEmpty) {
        if (_searchCache.length > 50) _searchCache.remove(_searchCache.keys.first);
        _searchCache[cacheKey] = combined;
      }

      return combined.isNotEmpty ? combined : localMatches;
    } catch (e) {
      debugPrint('[ArtistDiscoveryRepository] Search failed for "$cleanQuery": $e');
      return localMatches;
    }
  }

  @override
  Future<List<ArtistModel>> getRelatedArtists(String artistId) async {
    if (artistId.isEmpty) return [];

    if (_relatedCache.containsKey(artistId)) {
      return _relatedCache[artistId]!;
    }

    if (kIsWeb || _client == null) return [];

    try {
      final uri = Uri.parse('https://api.deezer.com/artist/$artistId/related?limit=10');
      final req = await _client!.getUrl(uri);
      final resp = await req.close();

      if (resp.statusCode != 200) return [];

      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final items = json['data'] as List<dynamic>? ?? [];

      final related = items
          .map((item) => ArtistModel.fromDeezer(Map<String, dynamic>.from(item as Map)))
          .where((a) => a.name.isNotEmpty && a.id.isNotEmpty)
          .toList();

      if (related.isNotEmpty) {
        if (_relatedCache.length > 50) _relatedCache.remove(_relatedCache.keys.first);
        _relatedCache[artistId] = related;
      }

      return related;
    } catch (e) {
      debugPrint('[ArtistDiscoveryRepository] Related fetch failed for "$artistId": $e');
      return [];
    }
  }

  /// Synchronously finds a curated artist by exact, alphanumeric, or partial name match.
  static ArtistModel? findCuratedByName(String name) {
    final clean = name.trim().toLowerCase();
    if (clean.isEmpty) return null;

    final normClean = clean.replaceAll(RegExp(r'[^a-z0-9]'), '');

    return _curatedArtists.where((a) => a.name.trim().toLowerCase() == clean).firstOrNull ??
        _curatedArtists.where((a) {
          final an = a.name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          return an.isNotEmpty &&
              (an == normClean ||
                  (normClean.length >= 3 && an.contains(normClean)) ||
                  (an.length >= 4 && normClean.contains(an)));
        }).firstOrNull;
  }

  /// Synchronously finds a curated artist by stable ID.
  static ArtistModel? findCuratedById(String id) {
    final clean = id.trim();
    if (clean.isEmpty) return null;
    return _curatedArtists.where((a) => a.id == clean).firstOrNull;
  }

  @override
  Future<ArtistModel?> getArtistDetails(String artistId) async {
    final cleanId = artistId.trim();
    if (cleanId.isEmpty) return null;

    // 1. Check curated list
    final curated = findCuratedById(cleanId);
    if (curated != null) return curated;

    // 2. Check in-memory cache
    if (_artistDetailsCache.containsKey(cleanId)) {
      return _artistDetailsCache[cleanId];
    }

    if (kIsWeb || _client == null) return null;

    // 3. Fetch from Deezer API
    try {
      final uri = Uri.parse('https://api.deezer.com/artist/$cleanId');
      final req = await _client!.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode != 200) return null;

      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json.containsKey('error') || !json.containsKey('id')) return null;

      final artist = ArtistModel.fromDeezer(json);
      if (_artistDetailsCache.length > 50) {
        _artistDetailsCache.remove(_artistDetailsCache.keys.first);
      }
      _artistDetailsCache[cleanId] = artist;
      return artist;
    } catch (e) {
      debugPrint('[ArtistDiscoveryRepository] Details fetch failed for "$cleanId": $e');
      return null;
    }
  }

  @override
  Future<List<ArtistAlbum>> getArtistAlbums(String artistId) async {
    final cleanId = artistId.trim();
    if (cleanId.isEmpty) return [];

    if (_albumsCache.containsKey(cleanId)) {
      return _albumsCache[cleanId]!;
    }

    if (kIsWeb || _client == null) return [];

    try {
      final uri = Uri.parse('https://api.deezer.com/artist/$cleanId/albums?limit=25');
      final req = await _client!.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode != 200) return [];

      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final items = json['data'] as List<dynamic>? ?? [];

      final albums = items
          .map((item) => ArtistAlbum.fromDeezer(Map<String, dynamic>.from(item as Map)))
          .where((a) => a.id.isNotEmpty && a.title.isNotEmpty)
          .toList();

      if (albums.isNotEmpty) {
        if (_albumsCache.length > 50) _albumsCache.remove(_albumsCache.keys.first);
        _albumsCache[cleanId] = albums;
      }
      return albums;
    } catch (e) {
      debugPrint('[ArtistDiscoveryRepository] Albums fetch failed for "$cleanId": $e');
      return [];
    }
  }

  @override
  Future<List<ArtistTopTrack>> getArtistTopTracks(String artistId) async {
    final cleanId = artistId.trim();
    if (cleanId.isEmpty) return [];

    if (_topTracksCache.containsKey(cleanId)) {
      return _topTracksCache[cleanId]!;
    }

    if (kIsWeb || _client == null) return [];

    try {
      final uri = Uri.parse('https://api.deezer.com/artist/$cleanId/top?limit=25');
      final req = await _client!.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode != 200) return [];

      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final items = json['data'] as List<dynamic>? ?? [];

      final tracks = items
          .map((item) => ArtistTopTrack.fromDeezer(Map<String, dynamic>.from(item as Map)))
          .where((t) => t.id.isNotEmpty && t.title.isNotEmpty)
          .toList();

      if (tracks.isNotEmpty) {
        if (_topTracksCache.length > 50) _topTracksCache.remove(_topTracksCache.keys.first);
        _topTracksCache[cleanId] = tracks;
      }
      return tracks;
    } catch (e) {
      debugPrint('[ArtistDiscoveryRepository] Top tracks fetch failed for "$cleanId": $e');
      return [];
    }
  }
}
