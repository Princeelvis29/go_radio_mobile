import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/station_model.dart';
import 'services/station_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await MobileAds.instance.initialize();
  
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.goradio.app.channel.audio',
    androidNotificationChannelName: 'Go Radio Live Playback',
    androidNotificationOngoing: true,
    androidShowNotificationBadge: true,
    androidNotificationIcon: 'mipmap/launcher_icon', 
  );

  runApp(const GoRadioApp());
}

class GoRadioApp extends StatelessWidget {
  const GoRadioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GO RADIO LIVE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFEF4444),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const RadioPlayerScreen(),
    );
  }
}

class RadioPlayerScreen extends StatefulWidget {
  const RadioPlayerScreen({super.key});

  @override
  State<RadioPlayerScreen> createState() => _RadioPlayerScreenState();
}

class _RadioPlayerScreenState extends State<RadioPlayerScreen> {
  int _currentIndex = 0;

  Station? _currentStation;
  List<Station> _favoriteStations = [];
  
  late SharedPreferences _prefs;

  String _currentStreamUrl = 'https://online.goradio.com.ng/listen/gr/radio.mp3';
  static const String _azuracastApiUrl = 'https://online.goradio.com.ng/api/nowplaying/1';
  static const String _defaultLogoPath = 'assets/logo.png';

  late AudioPlayer _audioPlayer;
  Timer? _metadataTimer;
  Timer? _sleepTimer;
  Timer? _countdownTimer;
  
  // 🚨 Alarm Clock Variables
  Timer? _alarmClockTimer;
  TimeOfDay? _alarmTime;
  bool _isAlarmActive = false;

  String _songTitle = 'Loading stream...';
  String _artistName = 'Connecting to Go Radio';
  String? _albumArtUrl;
  List<Map<String, String>> _songHistory = [];
  bool _isLoadingMetaData = true;

  int _selectedSleepMinutes = 0;
  int _sleepSecondsRemaining = 0;

  bool _showHistory = false;
  bool _showSchedule = false;

  final List<Map<String, String>> _programSchedule = const [
    {'time': '06:00 - 10:00', 'title': 'Morning Drive'},
    {'time': '10:00 - 14:00', 'title': 'Midday Groove'},
    {'time': '14:00 - 18:00', 'title': 'Afternoon Cruise'},
    {'time': '18:00 - 22:00', 'title': 'Evening Lounge'},
    {'time': '22:00 - 06:00', 'title': 'AutoDJ / Night Mix'},
  ];

  final List<Map<String, String>> _directories = const [
    {'name': 'TuneIn', 'url': 'https://tunein.com/radio/GoRadio-ng-s353013/'},
    {'name': 'MyTuner', 'url': 'https://mytuner-radio.com/radio/goradio-ng-518335/'},
    {'name': 'Streema', 'url': 'https://streema.com/radios/GoRadio_ng'},
    {'name': 'OnlineRadioBox', 'url': 'https://onlineradiobox.com/ng/go/'},
    {'name': 'GetmeRadio', 'url': 'https://www.getmeradio.com/stations/goradiong-11529'},
    {'name': 'RadioLine', 'url': 'https://www.radioline.co/en/radios/goradio_ng'},
    {'name': 'Live Radio Dublin', 'url': 'https://www.liveradio.ie/stations/goradio'},
    {'name': 'Live Radio UK', 'url': 'https://www.liveradio.uk/stations/goradio'},
    {'name': 'Radio Guide', 'url': 'https://www.radioguide.fm/internet-radio-nigeria/goradio-ng'},
    {'name': 'Radio Plug', 'url': 'https://www.radioplug.co.uk/channel/GoRad-ion'},
    {'name': 'Online Radio Play', 'url': 'https://online-radio-play.com/r112768_goradio_ng'},
    {'name': 'Forward My Stream', 'url': 'https://forwardmystream.com/station/goradio'},
    {'name': 'The OneStop Radio', 'url': 'https://theonestopradio.com/radio/goradio%20ng%20ng'},
    {'name': 'World Radio Browser', 'url': 'https://www.radio-browser.info/search?page=1&order=changetimestamp&reverse=true&hidebroken=false&name=goradio%20ng'},
    {'name': 'Radio.net', 'url': 'https://www.radio.net/s/goradiong'},
    {'name': 'Radio Nigeria', 'url': 'https://www.radio-nigeria.com/goradio-ng'},
    {'name': 'Listen Online Radio', 'url': 'https://listenonlineradio.com/ng/goradio-ng'},
    {'name': 'Radoxo Radio', 'url': 'https://radoxo.com/nigeria/goradio-ng'},
  ];

  @override
  void initState() {
    super.initState();
    _initPrefs(); 
    _audioPlayer = AudioPlayer();
    _initAudioPlayer();
    _fetchNowPlaying();
    _metadataTimer = Timer.periodic(const Duration(seconds: 15), (_) => _fetchNowPlaying());
    
    // 🚨 Initialize Alarm Checker (checks the time every 30 seconds)
    _alarmClockTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkAlarm());
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    
    final List<String> savedIds = _prefs.getStringList('favorite_station_ids') ?? [];
    
    final String? savedUrl = _prefs.getString('last_stream_url');
    final String? savedTitle = _prefs.getString('last_song_title');
    final String? savedArtist = _prefs.getString('last_artist_name');
    final String? savedArt = _prefs.getString('last_album_art');
    
    // Load saved alarm settings
    final int? alarmHour = _prefs.getInt('alarm_hour');
    final int? alarmMinute = _prefs.getInt('alarm_minute');
    final bool alarmActive = _prefs.getBool('alarm_active') ?? false;

    final allStations = await StationService.loadStations();
    
    if (mounted) {
      setState(() {
        _favoriteStations = allStations.where((station) => savedIds.contains(station.id.toString())).toList();
        
        if (savedUrl != null && savedUrl.isNotEmpty) {
          _currentStreamUrl = savedUrl;
          _songTitle = savedTitle ?? _songTitle;
          _artistName = savedArtist ?? _artistName;
          _albumArtUrl = savedArt ?? _albumArtUrl;
        }
        
        if (alarmHour != null && alarmMinute != null) {
          _alarmTime = TimeOfDay(hour: alarmHour, minute: alarmMinute);
          _isAlarmActive = alarmActive;
        }
      });
    }
  }

  void _saveLastPlayedState(String url, String title, String artist, String? art) {
    _prefs.setString('last_stream_url', url);
    _prefs.setString('last_song_title', title);
    _prefs.setString('last_artist_name', artist);
    if (art != null) {
      _prefs.setString('last_album_art', art);
    }
  }
  
  // 🚨 Save Alarm state to memory
  void _saveAlarmState() {
    if (_alarmTime != null) {
      _prefs.setInt('alarm_hour', _alarmTime!.hour);
      _prefs.setInt('alarm_minute', _alarmTime!.minute);
      _prefs.setBool('alarm_active', _isAlarmActive);
    }
  }

  // 🚨 Alarm Logic: Triggers playback when the time matches
  void _checkAlarm() async {
    if (_isAlarmActive && _alarmTime != null) {
      final now = TimeOfDay.now();
      if (now.hour == _alarmTime!.hour && now.minute == _alarmTime!.minute) {
        if (!_audioPlayer.playing) {
          if (_audioPlayer.audioSource == null) {
            await _setAudioSourceWithMetadata();
          }
          await _audioPlayer.play();
          
          if (mounted) {
            setState(() {
              _isAlarmActive = false; // Turn off alarm after it triggers
              _saveAlarmState();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⏰ Alarm! Waking up to Go Radio!'),
                backgroundColor: Color(0xFFEF4444),
                duration: Duration(seconds: 5),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _initAudioPlayer() async {
    try {
      await _setAudioSourceWithMetadata();
    } catch (e) {
      debugPrint('Error loading audio stream: $e');
    }
  }

  Future<void> _setAudioSourceWithMetadata() async {
    try {
      await _audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.parse(_currentStreamUrl),
          tag: MediaItem(
            id: 'goradio_live_stream',
            album: 'GO RADIO LIVE',
            title: _songTitle,
            artist: _artistName,
            artUri: _albumArtUrl != null && _albumArtUrl!.isNotEmpty
                ? Uri.tryParse(_albumArtUrl!)
                : null,
          ),
        ),
        preload: false,
      );
    } catch (e) {
      debugPrint('Error setting audio source metadata: $e');
    }
  }

  Future<void> _playSelectedStation(Station station) async {
    await _audioPlayer.stop();
    _metadataTimer?.cancel();

    setState(() {
      _currentStation = station; 
      _currentStreamUrl = station.streamUrl;
      _songTitle = station.name;
      _artistName = station.tagline;
      _albumArtUrl = station.coverArt;
      _isLoadingMetaData = false;
    });

    _saveLastPlayedState(station.streamUrl, station.name, station.tagline, station.coverArt);

    try {
      await _audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.parse(_currentStreamUrl),
          tag: MediaItem(
            id: station.id.toString(),
            album: station.category,
            title: station.name,
            artist: station.tagline,
            artUri: Uri.tryParse(station.coverArt),
          ),
        ),
        preload: false,
      );
      _audioPlayer.play();
    } catch (e) {
      debugPrint('Error playing new station: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error playing this station. Stream may be offline.')),
        );
      }
    }
  }

  void _toggleFavorite(Station station) {
    setState(() {
      if (_favoriteStations.any((s) => s.id == station.id)) {
        _favoriteStations.removeWhere((s) => s.id == station.id);
      } else {
        _favoriteStations.add(station);
      }
      final List<String> favoriteIds = _favoriteStations.map((s) => s.id.toString()).toList();
      _prefs.setStringList('favorite_station_ids', favoriteIds);
    });
  }

  @override
  void dispose() {
    _metadataTimer?.cancel();
    _sleepTimer?.cancel();
    _countdownTimer?.cancel();
    _alarmClockTimer?.cancel(); // Dispose alarm checker
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _fetchNowPlaying() async {
    try {
      final response = await http.get(Uri.parse(_azuracastApiUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final nowPlaying = data['now_playing'];
        final song = nowPlaying?['song'];
        final live = data['live'];

        final String title = song?['title'] ?? 'GO RADIO LIVE';
        final bool isLive = live?['is_live'] ?? false;
        final String streamer = live?['streamer_name'] ?? '';
        final String artist = isLive && streamer.isNotEmpty
            ? 'Live DJ: $streamer'
            : (song?['artist'] ?? 'GO RADIO');
        final String? artUrl = song?['art'];

        final List historyList = data['song_history'] ?? [];
        final List<Map<String, String>> parsedHistory = [];
        for (var item in historyList.take(5)) {
          final hSong = item['song'];
          if (hSong != null) {
            parsedHistory.add({
              'title': hSong['title'] ?? 'Unknown Track',
              'artist': hSong['artist'] ?? 'Unknown Artist',
              'art': hSong['art'] ?? '',
            });
          }
        }

        if (mounted) {
          setState(() {
            _songTitle = title;
            _artistName = artist;
            _albumArtUrl = artUrl;
            _songHistory = parsedHistory;
            _isLoadingMetaData = false;
          });

          if (_currentStation == null) {
            _saveLastPlayedState(_currentStreamUrl, title, artist, artUrl);
          }

          if (!_audioPlayer.playing) {
            _setAudioSourceWithMetadata();
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching metadata: $e');
      if (mounted) {
        setState(() {
          _isLoadingMetaData = false;
        });
      }
    }
  }

  Future<void> _launchExternalUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch $url')),
        );
      }
    }
  }

  void _shareApp() {
    final String trackInfo = _artistName.isNotEmpty && _artistName != 'Connecting to Go Radio'
        ? '$_songTitle by $_artistName'
        : _songTitle;
        
    Share.share(
      "I'm listening to Go Radio Live! Currently playing: $trackInfo. Download the app here: https://live.goradio.com.ng",
    );
  }

  void _requestSong() {
    final String trackInfo = _artistName.isNotEmpty && _artistName != 'Connecting to Go Radio'
        ? '$_songTitle by $_artistName'
        : _songTitle;
    
    final String message = Uri.encodeComponent(
      "Hello GoRadio! 🎵 I'm tuned in right now. Can I make a request or send a shoutout? (Currently playing: $trackInfo)"
    );
    
    _launchExternalUrl('https://wa.me/2348134839763?text=$message');
  }

  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _countdownTimer?.cancel();

    setState(() {
      _selectedSleepMinutes = minutes;
      _sleepSecondsRemaining = minutes * 60;
    });

    if (minutes == 0) return;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_sleepSecondsRemaining > 0) {
          _sleepSecondsRemaining--;
        } else {
          timer.cancel();
        }
      });
    });

    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      await _audioPlayer.pause();
      if (mounted) {
        setState(() {
          _selectedSleepMinutes = 0;
          _sleepSecondsRemaining = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sleep timer finished. Playback paused.')),
        );
      }
    });
  }

  String _formatTimerDisplay(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Center(
          child: Text('GO RADIO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('What do you want to do?', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 20),
            AdBannerWidget(),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              SystemChannels.platform.invokeMethod('SystemNavigator.pop');
            },
            child: const Text('Minimize', style: TextStyle(color: Color(0xFF25D366), fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              _audioPlayer.stop();
              SystemNavigator.pop();
            },
            child: const Text('Exit', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        _showExitDialog();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'GO RADIO',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF1E293B),
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share GO RADIO',
              onPressed: _shareApp,
            ),
          ],
        ),
        drawer: _buildSideDrawer(),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildLiveRadioTab(),
            ExploreScreen(
              onStationSelected: _playSelectedStation,
              favoriteStations: _favoriteStations,
              onToggleFavorite: _toggleFavorite,
            ),
            CategoryScreen(
              onStationSelected: _playSelectedStation,
              favoriteStations: _favoriteStations,
              onToggleFavorite: _toggleFavorite,
            ), 
            FavoriteScreen(
              favoriteStations: _favoriteStations,
              onStationSelected: _playSelectedStation,
              onToggleFavorite: _toggleFavorite,
            ), 
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_currentIndex != 0) _buildMiniPlayer(),
            const Divider(height: 1, thickness: 1, color: Colors.white10),
            _buildBottomNavBar(),
          ],
        ),
        floatingActionButton: _currentIndex == 0 
          ? FloatingActionButton.extended(
              onPressed: _requestSong,
              backgroundColor: const Color(0xFF25D366),
              icon: const Icon(Icons.chat, color: Colors.white),
              label: const Text('Live Request', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ) 
          : null,
      ),
    );
  }

  Widget _buildSideDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0F172A),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF1E293B)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Image.asset(_defaultLogoPath, height: 50, errorBuilder: (_, _, _) => const Icon(Icons.radio, size: 48, color: Colors.white)),
                const SizedBox(height: 12),
                const Text('GO RADIO', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined, color: Colors.white70),
            title: const Text('Home', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _currentIndex = 0);
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined, color: Colors.white70),
            title: const Text('Settings', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          const Divider(color: Colors.white10),
          const Padding(
            padding: EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0),
            child: Text('Socials', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.language, color: Colors.white70),
            title: const Text('Website', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _launchExternalUrl('https://goradio.com.ng');
            },
          ),
          ListTile(
            leading: const Icon(Icons.facebook, color: Colors.white70),
            title: const Text('Facebook', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: const Color(0xFF1E293B),
      selectedItemColor: const Color(0xFFEF4444),
      unselectedItemColor: Colors.white54,
      currentIndex: _currentIndex,
      onTap: (index) => setState(() => _currentIndex = index),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.explore_outlined), activeIcon: Icon(Icons.explore), label: 'Explore'),
        BottomNavigationBarItem(icon: Icon(Icons.grid_view), activeIcon: Icon(Icons.grid_view_rounded), label: 'Category'),
        BottomNavigationBarItem(icon: Icon(Icons.favorite_border), activeIcon: Icon(Icons.favorite), label: 'Favorite'),
      ],
    );
  }

  Widget _buildMiniPlayer() {
    return Container(
      color: const Color(0xFF1E293B),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: _albumArtUrl != null && _albumArtUrl!.isNotEmpty
                ? Image.network(_albumArtUrl!, width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, _, _) => Image.asset(_defaultLogoPath, width: 40, height: 40))
                : Image.asset(_defaultLogoPath, width: 40, height: 40, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_songTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(_artistName, style: const TextStyle(color: Colors.white54, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          StreamBuilder<PlayerState>(
            stream: _audioPlayer.playerStateStream,
            builder: (context, snapshot) {
              final playing = snapshot.data?.playing ?? false;
              final processingState = snapshot.data?.processingState;
              
              if (processingState == ProcessingState.loading || processingState == ProcessingState.buffering) {
                return const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Color(0xFFEF4444), strokeWidth: 2)),
                );
              }
              return IconButton(
                icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
                onPressed: () {
                  if (playing) {
                    _audioPlayer.pause();
                  } else {
                    _audioPlayer.play();
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLiveRadioTab() {
    return RefreshIndicator(
      onRefresh: _fetchNowPlaying,
      color: const Color(0xFFEF4444),
      backgroundColor: const Color(0xFF1E293B),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            padding: const EdgeInsets.all(20.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 15,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  _defaultLogoPath,
                  height: 60,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'LIVE ON AIR',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 220,
                    height: 220,
                    color: Colors.black26,
                    child: _albumArtUrl != null && _albumArtUrl!.isNotEmpty
                        ? Image.network(
                            _albumArtUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              String fallbackAsset = _currentStation?.coverArt ?? 'assets/logo.png';
                              return Image.asset(
                                fallbackAsset,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.radio,
                                  size: 80,
                                  color: Colors.white30,
                                ),
                              );
                            },
                          )
                        : Image.asset(
                            _currentStation?.coverArt ?? 'assets/logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.radio,
                              size: 80,
                              color: Colors.white30,
                            ),
                          ),
                  ),
                ),
                
                const SizedBox(height: 20),
                Text(
                  _songTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _artistName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      StreamBuilder<PlayerState>(
                        stream: _audioPlayer.playerStateStream,
                        builder: (context, snapshot) {
                          final playerState = snapshot.data;
                          final processingState = playerState?.processingState;
                          final playing = playerState?.playing ?? false;

                          Widget playButton;
                          if (processingState == ProcessingState.loading ||
                              processingState == ProcessingState.buffering) {
                            playButton = const SizedBox(
                              height: 64,
                              width: 64,
                              child: CircularProgressIndicator(color: Color(0xFFEF4444)),
                            );
                          } else {
                            playButton = Container(
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                iconSize: 42,
                                icon: Icon(
                                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                ),
                                onPressed: () async {
                                  if (playing) {
                                    await _audioPlayer.pause();
                                  } else {
                                    if (_audioPlayer.audioSource == null) {
                                      await _setAudioSourceWithMetadata();
                                    }
                                    await _audioPlayer.play();
                                  }
                                },
                              ),
                            );
                          }

                          return Column(
                            children: [
                              WebStyleEqualizer(isPlaying: playing),
                              const SizedBox(height: 24),
                              playButton,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      StreamBuilder<double>(
                        stream: _audioPlayer.volumeStream,
                        builder: (context, snapshot) {
                          final double volume = snapshot.data ?? 1.0;
                          return Row(
                            children: [
                              Icon(
                                volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                color: Colors.white54,
                                size: 20,
                              ),
                              Expanded(
                                child: Slider(
                                  value: volume,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: const Color(0xFFEF4444),
                                  inactiveColor: Colors.white10,
                                  onChanged: (newVolume) {
                                    _audioPlayer.setVolume(newVolume);
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'SLEEP TIMER:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white60,
                              letterSpacing: 1,
                            ),
                          ),
                          DropdownButton<int>(
                            value: _selectedSleepMinutes,
                            dropdownColor: const Color(0xFF1E293B),
                            underline: const SizedBox.shrink(),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('Off')),
                              DropdownMenuItem(value: 15, child: Text('15 Mins')),
                              DropdownMenuItem(value: 30, child: Text('30 Mins')),
                              DropdownMenuItem(value: 60, child: Text('1 Hour')),
                              DropdownMenuItem(value: 90, child: Text('90 Mins')),
                            ],
                            onChanged: (value) {
                              if (value != null) _setSleepTimer(value);
                            },
                          ),
                        ],
                      ),
                      if (_selectedSleepMinutes > 0)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Pausing in ${_formatTimerDisplay(_sleepSecondsRemaining)}',
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                          ),
                        ),
                      // 🚨 NEW ALARM CLOCK UI IMPLEMENTATION
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'ALARM CLOCK:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white60,
                              letterSpacing: 1,
                            ),
                          ),
                          Row(
                            children: [
                              if (_alarmTime != null)
                                Switch(
                                  value: _isAlarmActive,
                                  activeColor: const Color(0xFFEF4444),
                                  onChanged: (val) {
                                    setState(() {
                                      _isAlarmActive = val;
                                      _saveAlarmState();
                                    });
                                  },
                                ),
                              TextButton.icon(
                                onPressed: () async {
                                  final TimeOfDay? picked = await showTimePicker(
                                    context: context,
                                    initialTime: _alarmTime ?? TimeOfDay.now(),
                                    builder: (context, child) {
                                      return Theme(
                                        data: ThemeData.dark().copyWith(
                                          colorScheme: const ColorScheme.dark(
                                            primary: Color(0xFFEF4444),
                                            surface: Color(0xFF1E293B),
                                          ),
                                        ),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _alarmTime = picked;
                                      _isAlarmActive = true;
                                      _saveAlarmState();
                                    });
                                  }
                                },
                                icon: const Icon(Icons.alarm, color: Colors.white70, size: 16),
                                label: Text(
                                  _alarmTime != null ? _alarmTime!.format(context) : 'Set Alarm',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildAccordionHeader(
                  title: 'Recently Played',
                  isOpen: _showHistory,
                  onTap: () => setState(() => _showHistory = !_showHistory),
                ),
                if (_showHistory)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _songHistory.isEmpty
                        ? const Text(
                            'No recent history available',
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _songHistory.length,
                            separatorBuilder: (_, _) => const Divider(color: Colors.white10),
                            itemBuilder: (context, index) {
                              final track = _songHistory[index];
                              return Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: track['art'] != null && track['art']!.isNotEmpty
                                        ? Image.network(
                                            track['art']!,
                                            width: 38,
                                            height: 38,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) => Image.asset(
                                              _defaultLogoPath,
                                              width: 38,
                                              height: 38,
                                            ),
                                          )
                                        : Image.asset(_defaultLogoPath, width: 38, height: 38),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          track['title'] ?? '',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          track['artist'] ?? '',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white54,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                const SizedBox(height: 12),
                _buildAccordionHeader(
                  title: 'Program Schedule',
                  isOpen: _showSchedule,
                  onTap: () => setState(() => _showSchedule = !_showSchedule),
                ),
                if (_showSchedule)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _programSchedule.length,
                      separatorBuilder: (_, _) => const Divider(color: Colors.white10),
                      itemBuilder: (context, index) {
                        final item = _programSchedule[index];
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              item['time'] ?? '',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              item['title'] ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white10,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.share, size: 18, color: Colors.white),
                    label: const Text(
                      'SHARE GO RADIO',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _shareApp,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(color: Colors.white10),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'LISTEN ON YOUR FAVORITE APP',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white54,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 3.2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _directories.length,
                  itemBuilder: (context, index) {
                    final dir = _directories[index];
                    return InkWell(
                      onTap: () => _launchExternalUrl(dir['url']!),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          dir['name']!,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(color: Colors.white10),
                ),
                const Text(
                  'CONTACT US',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white54,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _launchExternalUrl('mailto:support@goradio.com.ng'),
                  child: const Text(
                    'support@goradio.com.ng',
                    style: TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _launchExternalUrl('tel:+2348134839763'),
                  child: const Text(
                    '+234 813 483 9763',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _launchExternalUrl('tel:+2348050344913'),
                  child: const Text(
                    '+234 805 034 4913',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '© GO RADIO. All Rights Reserved.',
                  style: TextStyle(color: Colors.white30, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => _launchExternalUrl('https://goradio.com.ng/privacy-policy'),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Privacy Policy',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ),
                    const Text(
                      '|',
                      style: TextStyle(color: Colors.white30, fontSize: 11),
                    ),
                    TextButton(
                      onPressed: () => _launchExternalUrl('https://goradio.com.ng/terms-of-service'),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Terms of Service',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccordionHeader({
    required String title,
    required bool isOpen,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
                letterSpacing: 1,
              ),
            ),
            Icon(
              isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: Colors.white70,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class ExploreScreen extends StatefulWidget {
  final Function(Station) onStationSelected;
  final List<Station> favoriteStations;
  final Function(Station) onToggleFavorite;

  const ExploreScreen({
    super.key, 
    required this.onStationSelected,
    required this.favoriteStations,
    required this.onToggleFavorite,
  });

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase();
              });
            },
            decoration: InputDecoration(
              icon: const Icon(Icons.search, color: Colors.white54),
              hintText: 'Search radios...',
              hintStyle: const TextStyle(color: Colors.white54),
              border: InputBorder.none,
              suffixIcon: _searchQuery.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white54),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
            ),
            style: const TextStyle(color: Colors.white),
          ),
        ),
        const SizedBox(height: 24),
        const AdBannerWidget(),
        const SizedBox(height: 24),
        Text(
          _searchQuery.isEmpty ? 'Featured radios' : 'Search Results', 
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)
        ),
        const SizedBox(height: 12),
        
        FutureBuilder<List<Station>>(
          future: StationService.loadStations(),
          builder: (context, snapshot) {
            
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFEF4444)),
                ),
              );
            } 
            else if (snapshot.hasError) {
              return Center(
                child: Text(
                  "Error loading stations: ${snapshot.error}",
                  style: const TextStyle(color: Colors.red),
                ),
              );
            } 
            else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(
                child: Text(
                  "No stations available right now.",
                  style: TextStyle(color: Colors.white54),
                ),
              );
            }

            final activeStations = snapshot.data!.where((station) {
              if (!station.isActive) return false;
              if (_searchQuery.isEmpty) return true;
              
              return station.name.toLowerCase().contains(_searchQuery) ||
                     station.category.toLowerCase().contains(_searchQuery) ||
                     station.tagline.toLowerCase().contains(_searchQuery);
            }).toList();

            if (activeStations.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text(
                    "No radios found for '$_searchQuery'",
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
              );
            }

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16.0,
                mainAxisSpacing: 16.0,
                childAspectRatio: 0.8,
              ),
              itemCount: activeStations.length,
              itemBuilder: (context, index) {
                final station = activeStations[index];
                final isFavorite = widget.favoriteStations.any((s) => s.id == station.id);
                
                return InkWell(
                  onTap: () => widget.onStationSelected(station),
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: const Color(0xFF1E293B),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                child: Image.asset(
                                  station.coverArt,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    color: const Color(0xFF0F172A),
                                    child: const Icon(Icons.radio, size: 40, color: Colors.white30),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    station.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    station.category,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: InkWell(
                          onTap: () => widget.onToggleFavorite(station),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isFavorite ? Icons.favorite : Icons.favorite_border,
                              color: isFavorite ? const Color(0xFFEF4444) : Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class CategoryScreen extends StatelessWidget {
  final Function(Station) onStationSelected;
  final List<Station> favoriteStations;
  final Function(Station) onToggleFavorite;

  const CategoryScreen({
    super.key, 
    required this.onStationSelected,
    required this.favoriteStations,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> categories = [
      {'title': 'Music', 'color': Colors.purple.shade400, 'icon': Icons.music_note},
      {'title': 'Classic', 'color': Colors.brown.shade400, 'icon': Icons.album},
      {'title': 'Education', 'color': Colors.teal.shade400, 'icon': Icons.school},
      {'title': 'Newscast', 'color': Colors.blueGrey.shade400, 'icon': Icons.article},
      {'title': 'Talk Show', 'color': Colors.deepOrange.shade400, 'icon': Icons.mic},
      {'title': 'Afrobeats', 'color': Colors.green.shade600, 'icon': Icons.public},
      {'title': 'Gospel', 'color': Colors.orangeAccent.shade400, 'icon': Icons.church}, 
    ];

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text(
          'Discover by category',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.2,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            return InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CategoryDetailScreen(
                      categoryName: category['title'],
                      onStationSelected: onStationSelected,
                      favoriteStations: favoriteStations,
                      onToggleFavorite: onToggleFavorite,
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  color: category['color'],
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(category['icon'], size: 40, color: Colors.white),
                    const SizedBox(height: 12),
                    Text(
                      category['title'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        const AdBannerWidget(),
      ],
    );
  }
}

class CategoryDetailScreen extends StatelessWidget {
  final String categoryName;
  final Function(Station) onStationSelected;
  final List<Station> favoriteStations;
  final Function(Station) onToggleFavorite;

  const CategoryDetailScreen({
    super.key,
    required this.categoryName,
    required this.onStationSelected,
    required this.favoriteStations,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          categoryName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: FutureBuilder<List<Station>>(
        future: StationService.loadStations(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFEF4444)));
          } else if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No stations found.", style: TextStyle(color: Colors.white54)));
          }

          final categoryStations = snapshot.data!.where((station) {
            if (!station.isActive) return false;
            
            String sCat = station.category.toLowerCase();
            String uiCat = categoryName.toLowerCase();
            
            if (sCat == uiCat) return true;
            if (uiCat == 'newscast' && sCat.contains('news')) return true;
            if (uiCat == 'classic' && (sCat == 'jazz' || sCat == 'classical')) return true;
            if (uiCat == 'music' && (sCat == 'pop' || sCat == 'jazz' || sCat == 'afrobeats' || sCat == 'gospel')) return true;
            
            return sCat.contains(uiCat) || uiCat.contains(sCat);
          }).toList();

          if (categoryStations.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.radio_outlined, size: 64, color: Colors.white.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text("No stations in $categoryName yet.", style: const TextStyle(color: Colors.white54)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: categoryStations.length,
            itemBuilder: (context, index) {
              final station = categoryStations[index];
              final isFavorite = favoriteStations.any((s) => s.id == station.id);

              return Card(
                color: const Color(0xFF1E293B),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      station.coverArt,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 56,
                        height: 56,
                        color: const Color(0xFF0F172A),
                        child: const Icon(Icons.radio, color: Colors.white30),
                      ),
                    ),
                  ),
                  title: Text(station.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text(station.tagline, style: const TextStyle(color: Colors.white54, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: isFavorite ? const Color(0xFFEF4444) : Colors.white54,
                        ),
                        onPressed: () => onToggleFavorite(station),
                      ),
                      const Icon(Icons.play_circle_fill, color: Color(0xFFEF4444), size: 32),
                    ],
                  ),
                  onTap: () {
                    onStationSelected(station);
                    Navigator.pop(context); 
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class FavoriteScreen extends StatelessWidget {
  final List<Station> favoriteStations;
  final Function(Station) onStationSelected;
  final Function(Station) onToggleFavorite;

  const FavoriteScreen({
    super.key,
    required this.favoriteStations,
    required this.onStationSelected,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    if (favoriteStations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border, size: 80, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text(
              'Whoops!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                "Your favorite list is empty because you haven't added any radios to the favorite menu.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: favoriteStations.length,
      itemBuilder: (context, index) {
        final station = favoriteStations[index];
        return Card(
          color: const Color(0xFF1E293B),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                station.coverArt,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 56,
                  height: 56,
                  color: const Color(0xFF0F172A),
                  child: const Icon(Icons.radio, color: Colors.white30),
                ),
              ),
            ),
            title: Text(station.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text(station.category, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.favorite, color: Color(0xFFEF4444)),
                  onPressed: () => onToggleFavorite(station),
                ),
                IconButton(
                  icon: const Icon(Icons.play_circle_fill, color: Colors.white, size: 32),
                  onPressed: () => onStationSelected(station),
                ),
              ],
            ),
            onTap: () => onStationSelected(station),
          ),
        );
      },
    );
  }
}

class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({super.key});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  final String _adUnitId = Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/6300978111' 
      : 'ca-app-pub-3940256099942544/2934735716'; 

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('BannerAd failed to load: $err');
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoaded && _bannerAd != null) {
      return Align(
        alignment: Alignment.center,
        child: SizedBox(
          width: _bannerAd!.size.width.toDouble(),
          height: _bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        ),
      );
    }
    return const SizedBox(height: 50); 
  }
}

class WebStyleEqualizer extends StatefulWidget {
  final bool isPlaying;
  final Color color;

  const WebStyleEqualizer({
    super.key,
    required this.isPlaying,
    this.color = const Color(0xFFEF4444),
  });

  @override
  State<WebStyleEqualizer> createState() => _WebStyleEqualizerState();
}

class _WebStyleEqualizerState extends State<WebStyleEqualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _random = Random();
  final int _barCount = 45; 
  late List<double> _heights;

  @override
  void initState() {
    super.initState();
    _heights = List.filled(_barCount, 4.0);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        if (widget.isPlaying) {
          setState(() {
            for (int i = 0; i < _barCount; i++) {
              _heights[i] = _random.nextDouble() * 35.0 + 4.0;
            }
          });
        }
      });

    if (widget.isPlaying) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(WebStyleEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        setState(() {
          _heights = List.filled(_barCount, 4.0); 
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center, 
        children: List.generate(_barCount, (index) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 3.0,
            height: _heights[index],
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(2.0),
            ),
          );
        }),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _dataSaver = false;
  bool _notifications = true;
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _dataSaver = _prefs.getBool('data_saver') ?? false;
      _notifications = _prefs.getBool('push_notifications') ?? true;
    });
  }

  void _toggleDataSaver(bool val) {
    setState(() => _dataSaver = val);
    _prefs.setBool('data_saver', val);
  }

  void _toggleNotifications(bool val) {
    setState(() => _notifications = val);
    _prefs.setBool('push_notifications', val);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text('Preferences', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          SwitchListTile(
            activeColor: const Color(0xFFEF4444),
            contentPadding: EdgeInsets.zero,
            title: const Text('Data Saver Mode', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: const Text('Stream audio at a lower bitrate to save mobile data.', style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _dataSaver,
            onChanged: _toggleDataSaver,
          ),
          SwitchListTile(
            activeColor: const Color(0xFFEF4444),
            contentPadding: EdgeInsets.zero,
            title: const Text('Push Notifications', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: const Text('Receive alerts for live shows and new stations.', style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _notifications,
            onChanged: _toggleNotifications,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Divider(color: Colors.white10),
          ),
          const Text('Storage & Data', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Clear Image Cache', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: const Text('Free up space by clearing cached station logos.', style: TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: const Icon(Icons.delete_outline, color: Colors.white54),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Image cache cleared successfully.'), duration: Duration(seconds: 2)),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Divider(color: Colors.white10),
          ),
          const Text('About', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('About GoRadio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text('Version 1.0.0\nDeveloped by Arktech Solutions', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Divider(color: Colors.white10),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Exit App', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
            subtitle: const Text('Close the application.', style: TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: const Icon(Icons.power_settings_new, color: Color(0xFFEF4444)),
            onTap: () {
              SystemChannels.platform.invokeMethod('SystemNavigator.pop');
            },
          ),
        ],
      ),
    );
  }
}