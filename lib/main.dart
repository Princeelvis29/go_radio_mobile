import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path_provider/path_provider.dart';

import 'models/station_model.dart';
import 'services/station_service.dart';

class AppColors {
  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
  static Color bg(BuildContext context) => isDark(context) ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  static Color card(BuildContext context) => isDark(context) ? const Color(0xFF1E293B) : Colors.white;
  static Color text(BuildContext context) => isDark(context) ? Colors.white : const Color(0xFF0F172A);
  static Color subText(BuildContext context) => isDark(context) ? Colors.white54 : Colors.black54;
  static Color border(BuildContext context) => isDark(context) ? Colors.white10 : Colors.black12;
  static const Color primary = Color(0xFFEF4444);
  static const Color success = Color(0xFF25D366);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('is_dark_mode') ?? true;
  GoRadioApp.themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  
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
  
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'GO RADIO LIVE',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData.light().copyWith(
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFEF4444),
              surface: Colors.white,
            ),
          ),
          darkTheme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFEF4444),
              surface: Color(0xFF1E293B),
            ),
          ),
          home: const RadioPlayerScreen(),
        );
      },
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

  Color _dominantColor = const Color(0xFF1E293B);

  bool _isRecording = false;
  http.Client? _recordClient;
  StreamSubscription<List<int>>? _recordSubscription;
  File? _recordedFile;
  int _recordedBytes = 0;

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
    _alarmClockTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkAlarm());
  }

  Future<void> _updatePalette() async {
    try {
      ImageProvider imageProvider;
      if (_albumArtUrl != null && _albumArtUrl!.isNotEmpty) {
        imageProvider = NetworkImage(_albumArtUrl!);
      } else {
        imageProvider = AssetImage(_currentStation?.coverArt ?? _defaultLogoPath);
      }

      final PaletteGenerator generator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 10,
      );

      if (mounted) {
        setState(() {
          _dominantColor = generator.dominantColor?.color ?? AppColors.card(context);
        });
      }
    } catch (e) {
      debugPrint('Error generating palette: $e');
    }
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    
    final List<String> savedIds = _prefs.getStringList('favorite_station_ids') ?? [];
    
    final String? savedUrl = _prefs.getString('last_stream_url');
    final String? savedTitle = _prefs.getString('last_song_title');
    final String? savedArtist = _prefs.getString('last_artist_name');
    final String? savedArt = _prefs.getString('last_album_art');
    
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
      _updatePalette(); 
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
  
  void _saveAlarmState() {
    if (_alarmTime != null) {
      _prefs.setInt('alarm_hour', _alarmTime!.hour);
      _prefs.setInt('alarm_minute', _alarmTime!.minute);
      _prefs.setBool('alarm_active', _isAlarmActive);
    }
  }

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
              _isAlarmActive = false;
              _saveAlarmState();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⏰ Alarm! Waking up to Go Radio!'),
                backgroundColor: AppColors.primary,
                duration: Duration(seconds: 5),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    setState(() {
      _isRecording = true;
      _recordedBytes = 0;
    });

    try {
      final directory = await getApplicationDocumentsDirectory();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      final fileName = 'GoRadio_${DateTime.now().millisecondsSinceEpoch}.mp3';
      _recordedFile = File('${directory.path}/$fileName');
      
      _recordClient = http.Client();
      final request = http.Request('GET', Uri.parse(_currentStreamUrl));
      final response = await _recordClient!.send(request);
      
      final sink = _recordedFile!.openWrite();
      
      _recordSubscription = response.stream.listen((chunk) {
        sink.add(chunk);
        if (mounted) {
          setState(() {
            _recordedBytes += chunk.length;
          });
        }
      }, onDone: () async {
        await sink.close();
        _stopRecording();
      }, onError: (e) async {
        debugPrint('Recording stream error: $e');
        await sink.close();
        _stopRecording();
      });
      
    } catch (e) {
      debugPrint('Failed to start recording: $e');
      _stopRecording();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start recording stream.')),
        );
      }
    }
  }

  void _stopRecording() {
    _recordSubscription?.cancel();
    _recordClient?.close();
    
    if (mounted) {
      setState(() {
        _isRecording = false;
      });
      
      if (_recordedFile != null && _recordedBytes > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recording saved!\nSize: ${(_recordedBytes / 1024 / 1024).toStringAsFixed(2)} MB'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 4),
          ),
        );
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
    if (_isRecording) {
      _stopRecording();
    }

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

    _updatePalette();
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
    _stopRecording(); 
    _metadataTimer?.cancel();
    _sleepTimer?.cancel();
    _countdownTimer?.cancel();
    _alarmClockTimer?.cancel(); 
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
          final bool albumArtChanged = _albumArtUrl != artUrl;
          
          setState(() {
            _songTitle = title;
            _artistName = artist;
            _albumArtUrl = artUrl;
            _songHistory = parsedHistory;
            _isLoadingMetaData = false;
          });

          if (_currentStation == null) {
            _saveLastPlayedState(_currentStreamUrl, title, artist, artUrl);
            if (albumArtChanged) _updatePalette();
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
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Center(
          child: Text('GO RADIO', style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('What do you want to do?', style: TextStyle(color: AppColors.subText(context))),
            const SizedBox(height: 20),
            const AdBannerWidget(),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppColors.subText(context))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              SystemChannels.platform.invokeMethod('SystemNavigator.pop');
            },
            child: const Text('Minimize', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              _audioPlayer.stop();
              SystemNavigator.pop();
            },
            child: const Text('Exit', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
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
          title: Text(
            'GO RADIO',
            style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          iconTheme: IconThemeData(color: AppColors.text(context)),
          centerTitle: true,
          backgroundColor: AppColors.card(context),
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
            Divider(height: 1, thickness: 1, color: AppColors.border(context)),
            _buildBottomNavBar(),
          ],
        ),
        floatingActionButton: _currentIndex == 0 
          ? FloatingActionButton.extended(
              onPressed: _requestSong,
              backgroundColor: AppColors.success,
              icon: const Icon(Icons.chat, color: Colors.white),
              label: const Text('Live Request', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ) 
          : null,
      ),
    );
  }

  Widget _buildSideDrawer() {
    return Drawer(
      backgroundColor: AppColors.bg(context),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: AppColors.card(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Image.asset(_defaultLogoPath, height: 50, errorBuilder: (_, _, _) => Icon(Icons.radio, size: 48, color: AppColors.text(context))),
                const SizedBox(height: 12),
                Text('GO RADIO', style: TextStyle(color: AppColors.text(context), fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ListTile(
            leading: Icon(Icons.home_outlined, color: AppColors.text(context).withOpacity(0.7)),
            title: Text('Home', style: TextStyle(color: AppColors.text(context))),
            onTap: () {
              Navigator.pop(context);
              setState(() => _currentIndex = 0);
            },
          ),
          // 🚨 Brand New Navigation Item for Recordings
          ListTile(
            leading: Icon(Icons.mic_none, color: AppColors.text(context).withOpacity(0.7)),
            title: Text('My Recordings', style: TextStyle(color: AppColors.text(context))),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RecordingsScreen()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.settings_outlined, color: AppColors.text(context).withOpacity(0.7)),
            title: Text('Settings', style: TextStyle(color: AppColors.text(context))),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          Divider(color: AppColors.border(context)),
          Padding(
            padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0),
            child: Text('Socials', style: TextStyle(color: AppColors.subText(context), fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: Icon(Icons.language, color: AppColors.text(context).withOpacity(0.7)),
            title: Text('Website', style: TextStyle(color: AppColors.text(context))),
            onTap: () {
              Navigator.pop(context);
              _launchExternalUrl('https://goradio.com.ng');
            },
          ),
          ListTile(
            leading: Icon(Icons.facebook, color: AppColors.text(context).withOpacity(0.7)),
            title: Text('Facebook', style: TextStyle(color: AppColors.text(context))),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: AppColors.card(context),
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.subText(context),
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
      color: AppColors.card(context),
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
                Text(_songTitle, style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(_artistName, style: TextStyle(color: AppColors.subText(context), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
                );
              }
              return IconButton(
                icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: AppColors.text(context)),
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
      color: AppColors.primary,
      backgroundColor: AppColors.card(context),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 800),
            constraints: const BoxConstraints(maxWidth: 450),
            padding: const EdgeInsets.all(20.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.isDark(context) ? _dominantColor.withOpacity(0.6) : _dominantColor.withOpacity(0.2),
                  AppColors.card(context),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border(context)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
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
                    Text(
                      'LIVE ON AIR',
                      style: TextStyle(
                        color: AppColors.text(context).withOpacity(0.7),
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
                    color: Colors.black12,
                    child: _albumArtUrl != null && _albumArtUrl!.isNotEmpty
                        ? Image.network(
                            _albumArtUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              String fallbackAsset = _currentStation?.coverArt ?? 'assets/logo.png';
                              return Image.asset(
                                fallbackAsset,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Icon(
                                  Icons.radio,
                                  size: 80,
                                  color: AppColors.subText(context),
                                ),
                              );
                            },
                          )
                        : Image.asset(
                            _currentStation?.coverArt ?? 'assets/logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.radio,
                              size: 80,
                              color: AppColors.subText(context),
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
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _artistName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.subText(context),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.bg(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border(context)),
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
                              child: CircularProgressIndicator(color: AppColors.primary),
                            );
                          } else {
                            playButton = Container(
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
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
                                color: AppColors.subText(context),
                                size: 20,
                              ),
                              Expanded(
                                child: Slider(
                                  value: volume,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: AppColors.primary,
                                  inactiveColor: AppColors.border(context),
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
                          Text(
                            'SLEEP TIMER:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.subText(context),
                              letterSpacing: 1,
                            ),
                          ),
                          DropdownButton<int>(
                            value: _selectedSleepMinutes,
                            dropdownColor: AppColors.card(context),
                            underline: const SizedBox.shrink(),
                            style: TextStyle(color: AppColors.text(context), fontSize: 12),
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
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ALARM CLOCK:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.subText(context),
                              letterSpacing: 1,
                            ),
                          ),
                          Row(
                            children: [
                              if (_alarmTime != null)
                                Switch(
                                  value: _isAlarmActive,
                                  activeColor: AppColors.primary,
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
                                        data: Theme.of(context).copyWith(
                                          colorScheme: Theme.of(context).colorScheme.copyWith(
                                            primary: AppColors.primary,
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
                                icon: Icon(Icons.alarm, color: AppColors.text(context).withOpacity(0.7), size: 16),
                                label: Text(
                                  _alarmTime != null ? _alarmTime!.format(context) : 'Set Alarm',
                                  style: TextStyle(color: AppColors.text(context), fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'RECORD STREAM:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.subText(context),
                              letterSpacing: 1,
                            ),
                          ),
                          Row(
                            children: [
                              if (_isRecording)
                                Text(
                                  '${(_recordedBytes / 1024 / 1024).toStringAsFixed(2)} MB  ',
                                  style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              IconButton(
                                icon: Icon(
                                  _isRecording ? Icons.stop_circle : Icons.fiber_manual_record, 
                                  color: _isRecording ? Colors.redAccent : AppColors.subText(context),
                                  size: 26,
                                ),
                                onPressed: _toggleRecording,
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
                      color: AppColors.bg(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _songHistory.isEmpty
                        ? Text(
                            'No recent history available',
                            style: TextStyle(color: AppColors.subText(context), fontSize: 12),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _songHistory.length,
                            separatorBuilder: (_, _) => Divider(color: AppColors.border(context)),
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
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: AppColors.text(context),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          track['artist'] ?? '',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.subText(context),
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
                      color: AppColors.bg(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _programSchedule.length,
                      separatorBuilder: (_, _) => Divider(color: AppColors.border(context)),
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
                              style: TextStyle(
                                color: AppColors.text(context),
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
                      backgroundColor: AppColors.isDark(context) ? Colors.white10 : Colors.black12,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: Icon(Icons.share, size: 18, color: AppColors.text(context)),
                    label: Text(
                      'SHARE GO RADIO',
                      style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold),
                    ),
                    onPressed: _shareApp,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Divider(color: AppColors.border(context)),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'LISTEN ON YOUR FAVORITE APP',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.subText(context),
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
                          color: AppColors.bg(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border(context)),
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          dir['name']!,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.text(context).withOpacity(0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Divider(color: AppColors.border(context)),
                ),
                Text(
                  'CONTACT US',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.subText(context),
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
                  child: Text(
                    '+234 813 483 9763',
                    style: TextStyle(color: AppColors.text(context).withOpacity(0.7), fontSize: 13),
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _launchExternalUrl('tel:+2348050344913'),
                  child: Text(
                    '+234 805 034 4913',
                    style: TextStyle(color: AppColors.text(context).withOpacity(0.7), fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '© GO RADIO. All Rights Reserved.',
                  style: TextStyle(color: AppColors.subText(context), fontSize: 11),
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
                      child: Text(
                        'Privacy Policy',
                        style: TextStyle(color: AppColors.subText(context), fontSize: 11),
                      ),
                    ),
                    Text(
                      '|',
                      style: TextStyle(color: AppColors.subText(context).withOpacity(0.4), fontSize: 11),
                    ),
                    TextButton(
                      onPressed: () => _launchExternalUrl('https://goradio.com.ng/terms-of-service'),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Terms of Service',
                        style: TextStyle(color: AppColors.subText(context), fontSize: 11),
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
          color: AppColors.bg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.text(context).withOpacity(0.7),
                letterSpacing: 1,
              ),
            ),
            Icon(
              isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: AppColors.text(context).withOpacity(0.7),
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
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase();
              });
            },
            decoration: InputDecoration(
              icon: Icon(Icons.search, color: AppColors.subText(context)),
              hintText: 'Search radios...',
              hintStyle: TextStyle(color: AppColors.subText(context)),
              border: InputBorder.none,
              suffixIcon: _searchQuery.isNotEmpty 
                  ? IconButton(
                      icon: Icon(Icons.clear, color: AppColors.subText(context)),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
            ),
            style: TextStyle(color: AppColors.text(context)),
          ),
        ),
        const SizedBox(height: 24),
        const AdBannerWidget(),
        const SizedBox(height: 24),
        Text(
          _searchQuery.isEmpty ? 'Featured radios' : 'Search Results', 
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text(context))
        ),
        const SizedBox(height: 12),
        
        FutureBuilder<List<Station>>(
          future: StationService.loadStations(),
          builder: (context, snapshot) {
            
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
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
              return Center(
                child: Text(
                  "No stations available right now.",
                  style: TextStyle(color: AppColors.subText(context)),
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
                    style: TextStyle(color: AppColors.subText(context)),
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
                          color: AppColors.card(context),
                          border: Border.all(color: AppColors.border(context)),
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
                                    color: AppColors.bg(context),
                                    child: Icon(Icons.radio, size: 40, color: AppColors.subText(context)),
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
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.text(context),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    station.category,
                                    style: TextStyle(
                                      color: AppColors.subText(context),
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
                              color: isFavorite ? AppColors.primary : Colors.white,
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
        Text(
          'Discover by category',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text(context)),
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
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text(context)),
        ),
        iconTheme: IconThemeData(color: AppColors.text(context)),
        backgroundColor: AppColors.card(context),
        elevation: 0,
      ),
      body: FutureBuilder<List<Station>>(
        future: StationService.loadStations(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          } else if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text("No stations found.", style: TextStyle(color: AppColors.subText(context))));
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
                  Icon(Icons.radio_outlined, size: 64, color: AppColors.subText(context).withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text("No stations in $categoryName yet.", style: TextStyle(color: AppColors.subText(context))),
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
                color: AppColors.card(context),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColors.border(context)),
                ),
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
                        color: AppColors.bg(context),
                        child: Icon(Icons.radio, color: AppColors.subText(context)),
                      ),
                    ),
                  ),
                  title: Text(station.name, style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold)),
                  subtitle: Text(station.tagline, style: TextStyle(color: AppColors.subText(context), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: isFavorite ? AppColors.primary : AppColors.subText(context),
                        ),
                        onPressed: () => onToggleFavorite(station),
                      ),
                      const Icon(Icons.play_circle_fill, color: AppColors.primary, size: 32),
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
            Icon(Icons.favorite_border, size: 80, color: AppColors.subText(context).withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              'Whoops!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.text(context)),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                "Your favorite list is empty because you haven't added any radios to the favorite menu.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.subText(context), height: 1.5),
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
          color: AppColors.card(context),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.border(context)),
          ),
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
                  color: AppColors.bg(context),
                  child: Icon(Icons.radio, color: AppColors.subText(context)),
                ),
              ),
            ),
            title: Text(station.name, style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold)),
            subtitle: Text(station.category, style: TextStyle(color: AppColors.subText(context), fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.favorite, color: AppColors.primary),
                  onPressed: () => onToggleFavorite(station),
                ),
                IconButton(
                  icon: Icon(Icons.play_circle_fill, color: AppColors.text(context), size: 32),
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
    this.color = AppColors.primary,
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

  void _showRequestDialog(BuildContext context) {
    final nameController = TextEditingController();
    final genreController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Request Station', style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: TextStyle(color: AppColors.text(context)),
                decoration: InputDecoration(
                  labelText: 'Station Name',
                  labelStyle: TextStyle(color: AppColors.subText(context)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border(context))),
                  focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: genreController,
                style: TextStyle(color: AppColors.text(context)),
                decoration: InputDecoration(
                  labelText: 'Genre / Location',
                  labelStyle: TextStyle(color: AppColors.subText(context)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border(context))),
                  focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: AppColors.subText(context))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () {
                final name = nameController.text;
                final genre = genreController.text;
                if(name.isNotEmpty) {
                  final message = Uri.encodeComponent("Hello GoRadio! I would like to request a new station addition:\n\nStation Name: $name\nGenre/Location: $genre");
                  launchUrl(Uri.parse('mailto:support@goradio.com.ng?subject=New Station Request&body=$message'));
                  Navigator.pop(context);
                }
              },
              child: const Text('Submit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text(context))),
        backgroundColor: AppColors.card(context),
        iconTheme: IconThemeData(color: AppColors.text(context)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text('Preferences', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          SwitchListTile(
            activeColor: AppColors.primary,
            contentPadding: EdgeInsets.zero,
            title: Text('Dark Mode', style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold)),
            subtitle: Text('Switch between crisp light and dark themes.', style: TextStyle(color: AppColors.subText(context), fontSize: 12)),
            value: GoRadioApp.themeNotifier.value == ThemeMode.dark,
            onChanged: (val) {
              setState(() {
                GoRadioApp.themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
                _prefs.setBool('is_dark_mode', val);
              });
            },
          ),
          SwitchListTile(
            activeColor: AppColors.primary,
            contentPadding: EdgeInsets.zero,
            title: Text('Data Saver Mode', style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold)),
            subtitle: Text('Stream audio at a lower bitrate to save mobile data.', style: TextStyle(color: AppColors.subText(context), fontSize: 12)),
            value: _dataSaver,
            onChanged: _toggleDataSaver,
          ),
          SwitchListTile(
            activeColor: AppColors.primary,
            contentPadding: EdgeInsets.zero,
            title: Text('Push Notifications', style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold)),
            subtitle: Text('Receive alerts for live shows and new stations.', style: TextStyle(color: AppColors.subText(context), fontSize: 12)),
            value: _notifications,
            onChanged: _toggleNotifications,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Divider(color: AppColors.border(context)),
          ),
          const Text('Engage', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Request a Station', style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold)),
            subtitle: Text('Suggest a new radio station for the app.', style: TextStyle(color: AppColors.subText(context), fontSize: 12)),
            trailing: Icon(Icons.add_circle_outline, color: AppColors.subText(context)),
            onTap: () => _showRequestDialog(context),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Divider(color: AppColors.border(context)),
          ),
          const Text('Storage & Data', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Clear Image Cache', style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold)),
            subtitle: Text('Free up space by clearing cached station logos.', style: TextStyle(color: AppColors.subText(context), fontSize: 12)),
            trailing: Icon(Icons.delete_outline, color: AppColors.subText(context)),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Image cache cleared successfully.'), duration: Duration(seconds: 2)),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Divider(color: AppColors.border(context)),
          ),
          const Text('About', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('About GoRadio', style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold)),
            subtitle: Text('Version 2.1.4\nDeveloped by Arktech Solutions', style: TextStyle(color: AppColors.subText(context), fontSize: 12)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Divider(color: AppColors.border(context)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Exit App', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            subtitle: Text('Close the application.', style: TextStyle(color: AppColors.subText(context), fontSize: 12)),
            trailing: const Icon(Icons.power_settings_new, color: AppColors.primary),
            onTap: () {
              SystemChannels.platform.invokeMethod('SystemNavigator.pop');
            },
          ),
        ],
      ),
    );
  }
}

// 🚨 BRAND NEW SCREEN: The complete My Recordings Library
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  List<File> _recordings = [];
  bool _isLoading = true;
  
  // Isolated player specifically for local offline playback
  final AudioPlayer _offlinePlayer = AudioPlayer();
  String? _playingPath;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
    
    // Automatically reset UI when an offline track finishes
    _offlinePlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _playingPath = null;
        });
      }
    });
  }

  Future<void> _loadRecordings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final List<FileSystemEntity> files = directory.listSync();
      
      final mp3Files = files
          .whereType<File>()
          .where((file) => file.path.endsWith('.mp3'))
          .toList();
      
      // Sort to show the newest recordings at the top
      mp3Files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      setState(() {
        _recordings = mp3Files;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading recordings: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _offlinePlayer.dispose();
    super.dispose();
  }
  
  void _deleteFile(File file) async {
    try {
      if (_playingPath == file.path) {
        await _offlinePlayer.stop();
        _playingPath = null;
      }
      await file.delete();
      _loadRecordings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Recording deleted.'),
            backgroundColor: AppColors.primary,
          )
        );
      }
    } catch(e) {
      debugPrint('Error deleting file: $e');
    }
  }

  void _shareFile(File file) {
    Share.shareXFiles([XFile(file.path)], text: 'Check out this live stream recording from Go Radio!');
  }

  Future<void> _togglePlay(File file) async {
    try {
      if (_playingPath == file.path) {
        if (_offlinePlayer.playing) {
          await _offlinePlayer.pause();
        } else {
          await _offlinePlayer.play();
        }
        setState(() {}); // Force UI update for play/pause icon
      } else {
        await _offlinePlayer.setFilePath(file.path);
        await _offlinePlayer.play();
        setState(() {
          _playingPath = file.path;
        });
      }
    } catch (e) {
      debugPrint('Playback error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to play this recording.'))
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Recordings', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text(context))),
        backgroundColor: AppColors.card(context),
        iconTheme: IconThemeData(color: AppColors.text(context)),
        elevation: 0,
      ),
      body: _isLoading 
        ? Center(child: CircularProgressIndicator(color: AppColors.primary))
        : _recordings.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mic_off_outlined, size: 80, color: AppColors.subText(context).withOpacity(0.3)),
                  const SizedBox(height: 16),
                  Text(
                    'No Recordings Yet',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text(context)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the record button on the player to save live streams.',
                    style: TextStyle(color: AppColors.subText(context)),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: _recordings.length,
              itemBuilder: (context, index) {
                final file = _recordings[index];
                final fileName = file.path.split('/').last;
                final fileSize = (file.lengthSync() / 1024 / 1024).toStringAsFixed(2);
                final dateModified = file.lastModifiedSync();
                final isPlayingThis = _playingPath == file.path;
                final isPlaying = isPlayingThis && _offlinePlayer.playing;

                return Card(
                  color: AppColors.card(context),
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: isPlayingThis ? AppColors.primary : AppColors.border(context)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: CircleAvatar(
                      backgroundColor: isPlayingThis ? AppColors.primary.withOpacity(0.2) : AppColors.bg(context),
                      child: Icon(
                        Icons.audio_file, 
                        color: isPlayingThis ? AppColors.primary : AppColors.subText(context)
                      ),
                    ),
                    title: Text(
                      fileName, 
                      style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        '$fileSize MB • ${_formatDate(dateModified)}', 
                        style: TextStyle(color: AppColors.subText(context), fontSize: 11)
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.share_outlined, color: AppColors.subText(context), size: 20),
                          onPressed: () => _shareFile(file),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: AppColors.subText(context), size: 20),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppColors.card(context),
                                title: Text('Delete Recording?', style: TextStyle(color: AppColors.text(context))),
                                content: Text('Are you sure you want to delete this audio file permanently?', style: TextStyle(color: AppColors.subText(context))),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: Text('Cancel', style: TextStyle(color: AppColors.subText(context))),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _deleteFile(file);
                                    },
                                    child: const Text('Delete', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              )
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, 
                            color: AppColors.primary, 
                            size: 36
                          ),
                          onPressed: () => _togglePlay(file),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}