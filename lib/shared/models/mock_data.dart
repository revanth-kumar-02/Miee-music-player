import 'album.dart';
import 'artist.dart';
import 'track.dart';

/// Isolated mock music repository data for rendering the Miee UI.
abstract class MockData {
  /// Featured track currently playing (used in Continue Listening and Mini Player).
  static const Track featuredTrack = Track(
    id: 'featured_1',
    title: 'Unsayable',
    artist: 'Brambles',
    imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuDQKldsJeEKwl2bDD2ObwcnJtHISxVlsLARTFkQTXrcTHlgVAOJolapm6AYGzwRT2fsmLpu8xryqPhXL4AVD6niG11_DVrcrKIj6DI16rzn_yI9XFyTjt3f7DqO7F467OoV1-l7cM4AJJQ-KQ2gESt_iBUWWwU5AJiia9iHG4hIqQSsI5z93Gtdn6FeokiNOTU4z1VGeZrd-7pGW6itiZ8tl4inegR-LIvpAtaCbp72Q2uiRhxTWbrNkGn5KYNGB2jdJvXPB4sQz5RA',
    duration: '4:12',
    progress: 0.33,
    isPlaying: false,
    isFavorited: true,
  );

  /// Recently played albums list.
  static const List<Album> recentlyPlayed = [
    Album(
      id: 'recent_1',
      title: 'Charcoal',
      artist: 'Brambles',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuDpRPle_hzLpc9-dokX1N2xDQ23Qe7AHZ584N1ELrDbQArSHXX6VoNEMWCe5TxpjGxIo6NPCtGKLQxHzDh-ZJVmc-KlpkDOdki0bvj5OrSxQk4dNR50ZeTCvN2FOZ7qMRSR4vWLNRM3_9uE-Er-7kShVruqUakwvVemPz45UaQLsYkOy4CC5iOOUvjlICzmjHSZ0luVKJky8iXKUxf615eAioFac6WRRH0TL3D9JBHU02KCKTHrJ0-xKEjQyLbUzj2u5hjuGR_r4V58',
      subtitle: 'Brambles',
    ),
    Album(
      id: 'recent_2',
      title: 'To Speak Of Solitude',
      artist: 'Brambles',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuBkcA_dAwGKnW0yAObcg5TAKNAef1F7BP-N6Oee0rl8NW0d-hVqjgqT9toXDedIA6NRrylvPc6JNeKyS7dIaXynxmYB63vSGDvcWsdoz8NwaPeYeybSEd6abOTRalXPIUgYwkB0jAh8i8ZmDqfGcIyo1u83yfIoFyOg5lmHciU06KLavHIzxR77oQsK-LJNvb2nRF7_9tomuFBuEQAiSPevwpXMBTGRw09F0Bu-C0fAs96precULvGoRzZqLPAfCXyRDrYl5KiAcj9E',
      subtitle: 'Brambles',
    ),
    Album(
      id: 'recent_3',
      title: 'Salt Photographs',
      artist: 'Brambles',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuC5cAQzC3d3DwfJwtmoQbF8wiUzv76pZsZI-o-g4n_Kq72qgB2k1GLUTuPmcqrF4REhvk_JIIW_jzpFcNPzo2a832PRpAkCFRhqU6rmvWQ9rOHFVt33CVanMLi0e33-Bo9W4ejDdhFXElGMQhuJQShAlR0DdI71XuudIJmjUFSjwA8wy9bG2679oqgZ9tujbzMKmBmRCwRioG7hgaWuDJ571OS0gEpuOp_TKvZ0gFL-_LtsBDV26-HAYuBJ0Vo8lpqsfErHNmYZZ58C',
      subtitle: 'Brambles',
    ),
  ];

  /// Recommended albums list (for horizontal scroll view).
  static const List<Album> recommendedAlbums = [
    Album(
      id: 'rec_1',
      title: 'Salt Photographs',
      artist: 'Brambles',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuC5cAQzC3d3DwfJwtmoQbF8wiUzv76pZsZI-o-g4n_Kq72qgB2k1GLUTuPmcqrF4REhvk_JIIW_jzpFcNPzo2a832PRpAkCFRhqU6rmvWQ9rOHFVt33CVanMLi0e33-Bo9W4ejDdhFXElGMQhuJQShAlR0DdI71XuudIJmjUFSjwA8wy9bG2679oqgZ9tujbzMKmBmRCwRioG7hgaWuDJ571OS0gEpuOp_TKvZ0gFL-_LtsBDV26-HAYuBJ0Vo8lpqsfErHNmYZZ58C',
      subtitle: 'Brambles',
    ),
    Album(
      id: 'rec_2',
      title: 'Charcoal',
      artist: 'Brambles',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuDpRPle_hzLpc9-dokX1N2xDQ23Qe7AHZ584N1ELrDbQArSHXX6VoNEMWCe5TxpjGxIo6NPCtGKLQxHzDh-ZJVmc-KlpkDOdki0bvj5OrSxQk4dNR50ZeTCvN2FOZ7qMRSR4vWLNRM3_9uE-Er-7kShVruqUakwvVemPz45UaQLsYkOy4CC5iOOUvjlICzmjHSZ0luVKJky8iXKUxf615eAioFac6WRRH0TL3D9JBHU02KCKTHrJ0-xKEjQyLbUzj2u5hjuGR_r4V58',
      subtitle: 'Brambles',
    ),
    Album(
      id: 'rec_3',
      title: 'To Speak Of Solitude',
      artist: 'Brambles',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuBkcA_dAwGKnW0yAObcg5TAKNAef1F7BP-N6Oee0rl8NW0d-hVqjgqT9toXDedIA6NRrylvPc6JNeKyS7dIaXynxmYB63vSGDvcWsdoz8NwaPeYeybSEd6abOTRalXPIUgYwkB0jAh8i8ZmDqfGcIyo1u83yfIoFyOg5lmHciU06KLavHIzxR77oQsK-LJNvb2nRF7_9tomuFBuEQAiSPevwpXMBTGRw09F0Bu-C0fAs96precULvGoRzZqLPAfCXyRDrYl5KiAcj9E',
      subtitle: 'Brambles',
    ),
  ];

  /// Bento Grid albums data.
  static const Album bentoHeroAlbum = Album(
    id: 'bento_hero',
    title: 'Ambient Collection',
    artist: 'Various Artists',
    imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuBPPkrB1pB9VQvy0FhwZeWN_67GM5blRn-inNaethL-YLP0n-jsX-GdjQ55u3j1IxTKVV6xeiyg3DuWbWJGclN_MAOliD7awUhjZarOqe9uA0_WN_JPayq7InA7Uv3ICAQxAkWwz5wmhVoGl4krqwGpZmEqK57fl8IYZbyGA8HDU9kg10A_ZLbOgg6dExEd-26DtJc0salicuDgH4ixEv7tL4aalPLmqkQPcH92FzxWo_Yeds3_PSflHG1zsFElu7AYHAjVbZWj1k9T',
    subtitle: 'Various Artists',
  );

  static const List<Album> bentoSubAlbums = [
    Album(
      id: 'bento_sub_1',
      title: 'Focus',
      artist: 'Various Artists',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuDEVcaZWEhuCXvnnpu30w2NniMmRhSBJkGX-ZKEYhvTAdzpX8dGltpxWIccW7lRB0Fil0HkP36brcaD4XphTliCPd8IbdJ43uRjt4xx7PBV5Nw9q-ztPn0tHhw5O2f1Vt97XTIML-FVwwRBeaQJRPEhbzAV85ql0seIkeZsmzxBoy2VSNZwPYK2jOIfZVVU1VQPDY--XMB4rk175Res2iwLNYVr32IFGBt8UUIENG5ZXxb2j_RZfXf2LMcKNg6jydAInQqTmb93SW8d',
    ),
    Album(
      id: 'bento_sub_2',
      title: 'Relax',
      artist: 'Various Artists',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuB_fOoQ1bRzcqe4ygeBEHpzonLGIFy3VdYh3utVVhRKYrcStLXBtYiBc1zBGa86c8ak9hrhzK4kjxI2LqiFmho8j02QqAc43dVWCMyIl-5P4vs14enuReddVTsBxp4vEqG_cWWG1Eyk6L7bnNI3hWnKzhryx_LsEkFr3lDrmoP8J7ssP2RflECf6GVUst-WSxbT9PaIzEbawLbycFWiqvEYp9KXb8EW3XYLP68mxT8HC0MGZVaY7vw_IcC2P0l08THg8Ut5I3qVmvom',
    ),
  ];

  /// Favorite Artists data.
  static const List<Artist> favoriteArtists = [
    Artist(
      id: 'artist_1',
      name: 'Brambles',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuDpRPle_hzLpc9-dokX1N2xDQ23Qe7AHZ584N1ELrDbQArSHXX6VoNEMWCe5TxpjGxIo6NPCtGKLQxHzDh-ZJVmc-KlpkDOdki0bvj5OrSxQk4dNR50ZeTCvN2FOZ7qMRSR4vWLNRM3_9uE-Er-7kShVruqUakwvVemPz45UaQLsYkOy4CC5iOOUvjlICzmjHSZ0luVKJky8iXKUxf615eAioFac6WRRH0TL3D9JBHU02KCKTHrJ0-xKEjQyLbUzj2u5hjuGR_r4V58',
    ),
    Artist(
      id: 'artist_2',
      name: 'Brambles Trio',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuBkcA_dAwGKnW0yAObcg5TAKNAef1F7BP-N6Oee0rl8NW0d-hVqjgqT9toXDedIA6NRrylvPc6JNeKyS7dIaXynxmYB63vSGDvcWsdoz8NwaPeYeybSEd6abOTRalXPIUgYwkB0jAh8i8ZmDqfGcIyo1u83yfIoFyOg5lmHciU06KLavHIzxR77oQsK-LJNvb2nRF7_9tomuFBuEQAiSPevwpXMBTGRw09F0Bu-C0fAs96precULvGoRzZqLPAfCXyRDrYl5KiAcj9E',
    ),
    Artist(
      id: 'artist_3',
      name: 'Brambles Ambient',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuC5cAQzC3d3DwfJwtmoQbF8wiUzv76pZsZI-o-g4n_Kq72qgB2k1GLUTuPmcqrF4REhvk_JIIW_jzpFcNPzo2a832PRpAkCFRhqU6rmvWQ9rOHFVt33CVanMLi0e33-Bo9W4ejDdhFXElGMQhuJQShAlR0DdI71XuudIJmjUFSjwA8wy9bG2679oqgZ9tujbzMKmBmRCwRioG7hgaWuDJ571OS0gEpuOp_TKvZ0gFL-_LtsBDV26-HAYuBJ0Vo8lpqsfErHNmYZZ58C',
    ),
  ];

  /// Recently added albums list for Library page.
  static const List<Album> recentlyAdded = [
    Album(
      id: 'added_1',
      title: 'Echoes of Silence',
      artist: 'Luna Drift',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuAs5SahYKlskYkHIGW8pNgRL5b6ybv0X9GtjYXf8zbmk8SmolhIP1-la75BRVa4OZmcn5jJHHCxwg2C_Q1iA_67xU2L2D-p-KJNkpczPEy2mSPYW3T00zFMpgv70lA3hc6c5CwFVPPWwx99BY74keJEwZJ8GbYHlC8lNlxAsHOxMXDe_-QFOydeocziVVwOLR2_5vwcZ29KfNnghXDmchcJocpMwejjUqk8p2eGspz-xaUiIGNhxh4JGB3KaiZ8u07RgWIHUbkuRcCw',
      subtitle: 'Luna Drift',
    ),
    Album(
      id: 'added_2',
      title: 'Concrete Patterns',
      artist: 'The Architects',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuDLa5Lkw-maiBfve1U_DLKUlzs_7MoKIJk2vtffegQlUPcJgWBzc_n8tbdd94jcl3i2-StXVdgRsgp-Uf2mjC49RIg7ArYLO3JAa4Et1D6K409YfxYQyHm0TBxxarlakO4VHWJZow6o960V3MXrvU6RZHOvrwG1pNoenHF00VG3w23Rg1l2mel1nGO71WM_fVqnPZj4wKtK9aHZmU7ZqUlUbRJJvuI4D6vvUumQ1h91BzFcQSrbO-wX_sAlvl8YBHMXUjASpJAd87-3',
      subtitle: 'The Architects',
    ),
    Album(
      id: 'added_3',
      title: 'Morning Haze',
      artist: 'Aura',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuA896rnVYCaIo5h12WKyclRAofgORTPjw3UfINRdb-ihChzwnXBizSe8xk55et7PV-_sn_kiCTov4mjsGKiqcrcXskIMch4wuEQfIwJbqlngMpvf5H-NG0m5DhUt0tgcaT-ilxjOqEWCVz57ZPiRozqxb7dLvd2di038GCzMarJ5b0zrbTKPxLn1a97X_j2QlWod_OPpE2tX6ssx7NeQn54jL6y1V4beUzHOlB4QEa37g6_f8Dpfjzxi3tUDOVsDnZPsSQojU11zEPv',
      subtitle: 'Aura',
    ),
    Album(
      id: 'added_4',
      title: 'Indigo Drops',
      artist: 'Synesthesia',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuC3cQh250bjWOijwQnlc-F0Xw3MaZigYZFiYvlqoS_3yJ8KLSVS-ESD_Rm-PupB2deeZ9j6XIrJC-HU_6VF_Oh2ps75NUdHKQlpsaP9UG_V7KbvxxaEld4X3LCukQ1WII4FS6sHpKR6x6d9CSR_v2jVVZvbwmALOgYFKzb7y1tVKkBGAFXDIUFVg65TxJTAq21j2mf8nvSwr3wdmwhfvowN_vBF7NvOUNUUTSAIDQIGZOvXMLMpecYVWpwjyogJvE-FNV586U8Rs0nb',
      subtitle: 'Synesthesia',
    ),
  ];

  /// Favorite tracks list for Library page.
  static const List<Track> favoriteSongs = [
    Track(
      id: 'fav_1',
      title: 'Glass House',
      artist: 'Fractal Beats',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuC0_uUNMdfAIyQ3JbVr21xsUKeC9NoN81NvKrXGbCisn9J1Tqcl18-pQ1CVloM2Qnw_nxI_2rKfV4AfFwlGjkX26ebMW9JpLZ5DNPEFR3UidQb0XTERth6X7rBNmWzsBZ0Z9VQd5llY_mqla01b1-k0Y4E1RxqXRp0j0US8PfrF2_Ys216sT2fXMCJy0N3quYvq7bkyLCIhN1R-B77xy9tjk1NMNL0vi01BGbY02_rKalSSGOrTY69vVdb29ck-1vgsQVTsYthMRDAM',
      duration: '3:42',
    ),
    Track(
      id: 'fav_2',
      title: 'Wireframe Dreams',
      artist: 'Nova',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuDJrQyhWnZN1McbotaaKMeVlz_JBHXmToUyv48eGVk4V7EO8M02-BFp7Alb4FsVXFMGPsGaWu_iyN5Yavew6BAUKB9uqE4HVjzE9vzn4onmZNSbBQbG-zzVgSLYCRV6YkMHjx0wVfNyg7neyQEaa-SB2OoR5Fb6BNZap3vqmR7qv4oONKgsnrhMIyRbbQdEDmGFuCpWzOvLtSgfSXgd78j92gSrq1bJaT-8fjBFCK2HjTt7HaryAiYY6y2U8CFIYmaoN229tGxpGcEK',
      duration: '4:15',
    ),
    Track(
      id: 'fav_3',
      title: 'Zenith',
      artist: 'Solitude',
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuDUkygHk9ZNP9nHvwIcfpLpBUUGgqZ88OtGy8grYd7RLhBpsVKDXkSJdNkXKmMa_NWCDV8JdG-a7Pu0ZSUPPxTcFy5moufuh5d6hs7fBeIBnxdeKgWWV7O6y6xrvO55Oac0GsiJ11q_zoAHLwt1QOLq7R49lHps10TVJbJHfebEhWa3lF2ZA0joi4yJ2Mjyg835c5sX9FU_Kaj2hWP1RU9xfXHUuPZfd3zZcBlZex6ZkbO1HkS5KiIqb2VR-had9uq02KLpgmQ5y6Zc',
      duration: '2:58',
    ),
  ];

  /// Track details for Library mini player.
  static const Track libraryTrack = Track(
    id: 'library_mini_1',
    title: 'Midnight City',
    artist: 'M83',
    imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuDEJL3-a_CVAEiwUCarY6vixWZXzScM8QhPMF7ZY4XGaIv1NFVj0VZGDHYCfP_qaHjCWPY0LrlnToZbyPGRmKL4HD9-Y6kUMzd0a7nYauV-uqs1XdO_SZLFI-NqOVf2Ro5j3EqCVw9NyTY8Alju2aiWpQDcwrpZANtW3tz_woC2e_vRtxkW5QETA4MXSpKCz_ajBxyFKlAOrpGLRriJk0M4AnSANJXmzCgYg4VdSlIX5Gr3W4TpuyR4KM_twIqdXy4q-njOrzCTW-WY',
    duration: '4:03',
    progress: 0.45,
    isPlaying: false,
    isFavorited: false,
  );
}
