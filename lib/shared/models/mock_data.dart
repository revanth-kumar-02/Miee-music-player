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
}
