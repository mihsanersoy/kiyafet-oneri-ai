import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'core/background/weather_alert_worker.dart';
import 'core/network/api_client.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/storage/secure_storage_service.dart';
import 'core/widgets/global_location_autocomplete.dart';
import 'features/auth/auth_service.dart';
import 'features/routine/routine_service.dart';

const Color kMatteWhite = Color(0xFFF1F5F9);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalNotificationService.instance.init();
  await WeatherAlertWorker.initializeAndSchedule();
  runApp(const OptiWearApp());
}

class OptiWearApp extends StatefulWidget {
  const OptiWearApp({super.key});

  @override
  State<OptiWearApp> createState() => _OptiWearAppState();
}

class _OptiWearAppState extends State<OptiWearApp> {
  late final SecureStorageService _storage;
  late final ApiClient _apiClient;
  late final AuthService _authService;
  late final RoutineService _routineService;

  Map<String, dynamic>? _currentUser;
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _storage = SecureStorageService();
    _apiClient = ApiClient(storage: _storage);
    _authService = AuthService(apiClient: _apiClient, storage: _storage);
    _routineService = RoutineService(apiClient: _apiClient);
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final token = await _storage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        final profile = await _authService.getMyProfile();
        if (mounted) {
          setState(() => _currentUser = profile);
        }
      }
    } catch (_) {
      await _storage.clearSession();
    } finally {
      if (mounted) {
        setState(() => _checkingSession = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OptiWear',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF38BDF8),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF020617),
      ),
      home: _checkingSession
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : _currentUser == null
              ? AuthScreen(
                  authService: _authService,
                  onAuthenticated: (user) => setState(() => _currentUser = user),
                )
              : RoutineDashboardScreen(
                  user: _currentUser!,
                  authService: _authService,
                  routineService: _routineService,
                  onUserUpdated: (updated) => setState(() => _currentUser = updated),
                  onLogout: () => setState(() => _currentUser = null),
                ),
    );
  }
}

Widget buildUserAvatarWidget({
  required String? avatarBase64,
  double radius = 18,
}) {
  if (avatarBase64 != null && avatarBase64.trim().isNotEmpty) {
    try {
      final bytes = base64Decode(avatarBase64.trim());
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.white,
        backgroundImage: MemoryImage(bytes),
      );
    } catch (_) {}
  }
  return CircleAvatar(
    radius: radius,
    backgroundColor: Colors.white,
    child: Icon(
      Icons.person,
      color: const Color(0xFF0F172A),
      size: radius * 1.25,
    ),
  );
}

class AuthScreen extends StatefulWidget {
  final AuthService authService;
  final ValueChanged<Map<String, dynamic>> onAuthenticated;

  const AuthScreen({
    super.key,
    required this.authService,
    required this.onAuthenticated,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _awaitingOtp = false;
  bool _loading = false;
  String? _errorMessage;
  String? _infoMessage;
  String _pendingEmail = '';

  String? _nameError;
  String? _phoneError;
  String? _emailError;
  String? _passwordError;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  static final RegExp _emailRegex =
      RegExp(r'^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$');
  static final RegExp _phoneRegex = RegExp(r'^\+?[0-9]{10,15}$');
  static final RegExp _upperRegex = RegExp(r'[A-ZÇĞİÖŞÜ]');
  static final RegExp _lowerRegex = RegExp(r'[a-zçğıöşü]');
  static final RegExp _digitRegex = RegExp(r'\d');

  bool _validateFields() {
    String? nameErr;
    String? phoneErr;
    String? emailErr;
    String? passErr;

    final email = _emailCtrl.text.trim();
    final pass = _passwordCtrl.text;

    if (!_isLogin) {
      final name = _nameCtrl.text.trim();
      final phone = _phoneCtrl.text.replaceAll(RegExp(r'[\s\-\(\)]'), '');

      if (name.length < 2) {
        nameErr = 'Lütfen adınızı ve soyadınızı girin (en az 2 karakter).';
      }
      if (!_phoneRegex.hasMatch(phone)) {
        phoneErr = 'Telefon 10-15 rakam olmalıdır (Örn: +905551234567 veya 05551234567).';
      }
    }

    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      emailErr = 'Geçerli bir e-posta adresi girin (Örn: ad@ornek.com).';
    }

    if (_isLogin) {
      if (pass.isEmpty) {
        passErr = 'Lütfen şifrenizi girin.';
      }
    } else {
      final missing = <String>[];
      if (pass.length < 8) missing.add('en az 8 karakter');
      if (!_upperRegex.hasMatch(pass)) missing.add('1 büyük harf');
      if (!_lowerRegex.hasMatch(pass)) missing.add('1 küçük harf');
      if (!_digitRegex.hasMatch(pass)) missing.add('1 rakam');
      if (missing.isNotEmpty) {
        passErr = 'Şifre gereksinimi eksik: ${missing.join(", ")} içermelidir.';
      }
    }

    setState(() {
      _nameError = nameErr;
      _phoneError = phoneErr;
      _emailError = emailErr;
      _passwordError = passErr;
    });

    return nameErr == null && phoneErr == null && emailErr == null && passErr == null;
  }

  String _extractError(Object err) {
    if (err is DioException) {
      final data = err.response?.data;
      if (data is Map && data['detail'] != null) {
        final detail = data['detail'];
        if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          if (first is Map && first['msg'] != null) {
            return first['msg'].toString();
          }
        }
        return detail.toString();
      }
    }
    return 'İşlem sırasında bir hata oluştu. Lütfen bilgilerinizi kontrol edin.';
  }

  Future<void> _submit() async {
    setState(() {
      _errorMessage = null;
      _infoMessage = null;
    });

    if (!_validateFields()) {
      return;
    }

    setState(() => _loading = true);
    try {
      if (_isLogin) {
        final user = await widget.authService.login(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
        );
        widget.onAuthenticated(user);
      } else {
        final regRes = await widget.authService.register(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
          fullName: _nameCtrl.text,
          phoneNumber: _phoneCtrl.text,
        );
        setState(() {
          _pendingEmail = (regRes['email'] ?? _emailCtrl.text.trim()).toString();
          _awaitingOtp = true;
          _infoMessage = regRes['mesaj']?.toString() ??
              'E-postanıza gelen 6 haneli doğrulama kodunu girin.';
        });
      }
    } catch (e) {
      final errMsg = _extractError(e);
      if (e is DioException &&
          e.response?.statusCode == 403 &&
          errMsg.toLowerCase().contains('doğrulanmamış')) {
        setState(() {
          _pendingEmail = _emailCtrl.text.trim();
          _awaitingOtp = true;
          _infoMessage = errMsg;
        });
      } else {
        setState(() => _errorMessage = errMsg);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _verifyOtpCode() async {
    final code = _otpCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Lütfen 6 haneli doğrulama kodunu eksiksiz girin.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final user = await widget.authService.verifyEmail(
        email: _pendingEmail,
        otpCode: code,
      );
      widget.onAuthenticated(user);
    } catch (e) {
      setState(() => _errorMessage = _extractError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _buildInlineError(String? errorText) {
    if (errorText == null || errorText.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 5, left: 4, right: 4),
      child: Text(
        errorText,
        softWrap: true,
        style: const TextStyle(
          color: Colors.redAccent,
          fontSize: 11.5,
          height: 1.35,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              color: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withOpacity(0.12)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Image.asset(
                            'assets/images/logo.png',
                            height: 28,
                            width: 28,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'OptiWear',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: kMatteWhite,
                                letterSpacing: 0.4,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _awaitingOtp
                          ? 'E-postanıza gelen 6 haneli kodu girin ($_pendingEmail)'
                          : (_isLogin
                              ? 'Güvenli hesabınıza giriş yapın'
                              : 'Yeni OptiWear hesabı oluşturun'),
                      softWrap: true,
                      style: const TextStyle(color: Colors.white70, fontSize: 13.5),
                    ),
                    const SizedBox(height: 20),
                    if (_infoMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF38BDF8)),
                        ),
                        child: Text(
                          _infoMessage!,
                          softWrap: true,
                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12.5),
                        ),
                      ),
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.redAccent),
                        ),
                        child: Text(
                          _errorMessage!,
                          softWrap: true,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
                        ),
                      ),
                    if (_awaitingOtp) ...[
                      TextField(
                        controller: _otpCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          letterSpacing: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          labelText: '6 Haneli Doğrulama Kodu',
                          prefixIcon: Icon(Icons.verified_user_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loading ? null : _verifyOtpCode,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            _loading ? 'Doğrulanıyor...' : 'Kodu Doğrula ve Giriş Yap',
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _awaitingOtp = false;
                          _errorMessage = null;
                          _infoMessage = null;
                        }),
                        child: const Text('← Bilgileri Düzenle / Geri Dön'),
                      ),
                    ] else ...[
                      if (!_isLogin) ...[
                        TextField(
                          controller: _nameCtrl,
                          onChanged: (_) {
                            if (_nameError != null) setState(() => _nameError = null);
                          },
                          decoration: const InputDecoration(
                            labelText: 'Ad Soyad',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        _buildInlineError(_nameError),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          onChanged: (_) {
                            if (_phoneError != null) setState(() => _phoneError = null);
                          },
                          decoration: const InputDecoration(
                            labelText: 'Telefon Numarası',
                            hintText: '+905551234567',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        _buildInlineError(_phoneError),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (_) {
                          if (_emailError != null) setState(() => _emailError = null);
                        },
                        decoration: const InputDecoration(
                          labelText: 'E-posta Adresi',
                          hintText: 'ornek@eposta.com',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      _buildInlineError(_emailError),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: true,
                        onChanged: (_) {
                          if (_passwordError != null) setState(() => _passwordError = null);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Şifre',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      if (!_isLogin)
                        const Padding(
                          padding: EdgeInsets.only(top: 6, left: 4, right: 4),
                          child: Text(
                            'Şifreniz en az 8 karakter uzunluğunda olmalı; en az 1 büyük harf, 1 küçük harf ve 1 rakam içermelidir.',
                            softWrap: true,
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 11.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      _buildInlineError(_passwordError),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(_loading
                              ? 'İşleniyor...'
                              : (_isLogin ? 'Giriş Yap' : 'Kayıt Ol')),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _isLogin = !_isLogin;
                          _errorMessage = null;
                          _infoMessage = null;
                          _nameError = null;
                          _phoneError = null;
                          _emailError = null;
                          _passwordError = null;
                        }),
                        child: Text(_isLogin
                            ? 'Hesabınız yok mu? Kayıt Olun'
                            : 'Zaten hesabınız var mı? Giriş Yapın'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RoutineDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final AuthService authService;
  final RoutineService routineService;
  final ValueChanged<Map<String, dynamic>> onUserUpdated;
  final VoidCallback onLogout;

  const RoutineDashboardScreen({
    super.key,
    required this.user,
    required this.authService,
    required this.routineService,
    required this.onUserUpdated,
    required this.onLogout,
  });

  @override
  State<RoutineDashboardScreen> createState() => _RoutineDashboardScreenState();
}

class _RoutineDashboardScreenState extends State<RoutineDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedTabIndex = 0;

  // Sekme 1: Kombin & Rutinlerim (Varsayılan konum Profilim'den otomatik gelir, tek seferlik değiştirilebilir)
  late GlobalLocationSelection _homeLocation;
  final _heightCtrl = TextEditingController(text: '175');
  final _weightCtrl = TextEditingController(text: '75');
  String _sweating = 'Hayır';

  final _customTitleCtrl = TextEditingController(text: 'Sabah Uyanma');
  final _customTimeCtrl = TextEditingController(text: '07:30');
  int _selectedLeadMinutes = 15;
  static const List<int> _leadMinuteOptions = [5, 10, 15, 20, 30, 45, 60, 90, 120];
  static const List<String> _dayShortLabels = ['P', 'S', 'Ç', 'P', 'C', 'C', 'P'];
  static const List<String> _dayFullCodes = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
  final List<bool> _selectedDays = [true, true, true, true, true, false, false];
  List<Map<String, dynamic>> _customRoutines = [];

  // Sekme 2: Seyahat Valizi Modu (Uluslararası Konum Arama)
  GlobalLocationSelection _travelLocation = const GlobalLocationSelection(
    name: 'Antalya',
    admin1: 'Antalya',
    country: 'Türkiye',
    latitude: 36.8841,
    longitude: 30.7056,
    displayName: 'Antalya, Türkiye',
  );
  final _travelStartCtrl = TextEditingController(text: '2026-11-26');
  final _travelEndCtrl = TextEditingController(text: '2026-11-30');
  Map<String, dynamic>? _travelResult;
  bool _travelLoading = false;

  // Sekme 3: Hızlı Hava Durumu Arama (Uluslararası Konum Arama)
  GlobalLocationSelection _quickLocation = const GlobalLocationSelection(
    name: 'Ankara',
    admin1: 'Ankara',
    country: 'Türkiye',
    latitude: 39.9208,
    longitude: 32.8541,
    displayName: 'Ankara, Türkiye',
  );
  Map<String, dynamic>? _quickWeatherResult;
  bool _quickLoading = false;

  bool _loading = false;
  String? _statusMessage;
  Map<String, dynamic>? _morningBriefResult;

  @override
  void initState() {
    super.initState();
    _syncDefaultLocationFromUser(widget.user);
    _loadAllRoutines();
  }

  void _syncDefaultLocationFromUser(Map<String, dynamic> userMap) {
    final name = (userMap['default_location_name'] ?? 'İstanbul').toString();
    final admin1 = (userMap['default_admin1'] ?? '').toString();
    final country = (userMap['default_country'] ?? 'Türkiye').toString();
    final lat = (userMap['default_lat'] as num?)?.toDouble() ?? 41.0082;
    final lon = (userMap['default_lon'] as num?)?.toDouble() ?? 28.9784;
    final parts = [name, if (admin1.isNotEmpty && admin1 != name) admin1, if (country.isNotEmpty) country];

    _homeLocation = GlobalLocationSelection(
      name: name,
      admin1: admin1,
      country: country,
      latitude: lat,
      longitude: lon,
      displayName: parts.join(', '),
    );
  }

  Future<void> _loadAllRoutines() async {
    try {
      final r = await widget.routineService.getMyRoutine();
      final customList = await widget.routineService.getCustomRoutines();
      if (!mounted) return;
      setState(() {
        _heightCtrl.text = (r['boy'] ?? 175).toString();
        _weightCtrl.text = (r['kilo'] ?? 75).toString();
        _sweating = (r['terleme_egilimi'] ?? 'Hayır').toString();
        _customRoutines = customList;
      });
      await WeatherAlertWorker.initializeAndSchedule(
        city: _homeLocation.name,
        district: _homeLocation.admin1,
      );
    } catch (_) {}
  }

  List<Color> _weatherGradient(String? status) {
    switch (status) {
      case 'Güneşli':
        return [const Color(0xFF0284C7), const Color(0xFFD97706)];
      case 'Yağmurlu':
        return [const Color(0xFF1E3A8A), const Color(0xFF0F172A)];
      case 'Karlı':
        return [const Color(0xFF38BDF8), const Color(0xFF1E293B)];
      case 'Rüzgarlı':
        return [const Color(0xFF0F766E), const Color(0xFF0F172A)];
      case 'Dolu':
        return [const Color(0xFF4C1D95), const Color(0xFF0F172A)];
      case 'Soğuk/Ayaz':
      default:
        return [const Color(0xFF1E40AF), const Color(0xFF020617)];
    }
  }

  Future<void> _searchQuickWeather() async {
    setState(() => _quickLoading = true);
    try {
      final res = await widget.routineService.fetchQuickWeather(
        sehir: _quickLocation.name,
        ilce: _quickLocation.admin1,
        lat: _quickLocation.latitude,
        lon: _quickLocation.longitude,
      );
      if (mounted) setState(() => _quickWeatherResult = res);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Konum hava durumu alınamadı.')),
        );
      }
    } finally {
      if (mounted) setState(() => _quickLoading = false);
    }
  }

  Future<void> _pickTravelDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 15)),
    );
    if (picked != null) {
      String fmt(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      setState(() {
        _travelStartCtrl.text = fmt(picked.start);
        _travelEndCtrl.text = fmt(picked.end);
      });
    }
  }

  Future<void> _generateTravelPackingList() async {
    setState(() => _travelLoading = true);
    try {
      final res = await widget.routineService.getTravelPackingRecommendation(
        hedefSehir: _travelLocation.displayName,
        hedefIlce: _travelLocation.admin1,
        lat: _travelLocation.latitude,
        lon: _travelLocation.longitude,
        baslangicTarihi: _travelStartCtrl.text,
        bitisTarihi: _travelEndCtrl.text,
        boy: double.tryParse(_heightCtrl.text) ?? 175.0,
        kilo: double.tryParse(_weightCtrl.text) ?? 75.0,
        terlemeEgilimi: _sweating,
      );
      if (mounted) setState(() => _travelResult = res);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seyahat valizi önerisi alınırken hata oluştu.')),
        );
      }
    } finally {
      if (mounted) setState(() => _travelLoading = false);
    }
  }

  Future<void> _pickCustomRoutineTime() async {
    final parts = _customTimeCtrl.text.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 7,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '30') ?? 30,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final hh = picked.hour.toString().padLeft(2, '0');
      final mm = picked.minute.toString().padLeft(2, '0');
      setState(() => _customTimeCtrl.text = '$hh:$mm');
    }
  }

  String _getSelectedDaysString() {
    final chosen = <String>[];
    for (int i = 0; i < _selectedDays.length; i++) {
      if (_selectedDays[i]) {
        chosen.add(_dayFullCodes[i]);
      }
    }
    return chosen.isEmpty ? 'Pzt,Sal,Çar,Per,Cum' : chosen.join(',');
  }

  String _shortenTo34Sentences(String rawText) {
    final cleaned = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return '';
    final sentences = cleaned
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return sentences.take(4).join(' ');
  }

  String _getCurrentSystemCommentSummary([String? fallbackFromRoutine]) {
    if (_morningBriefResult != null && _morningBriefResult!['oneri'] != null) {
      final s = _shortenTo34Sentences(_morningBriefResult!['oneri'].toString());
      if (s.isNotEmpty) return s;
    }
    if (fallbackFromRoutine != null && fallbackFromRoutine.trim().isNotEmpty) {
      return _shortenTo34Sentences(fallbackFromRoutine);
    }
    if (_customRoutines.isNotEmpty) {
      final lastMsg = _customRoutines.first['notification_message']?.toString() ?? '';
      if (lastMsg.trim().isNotEmpty) return _shortenTo34Sentences(lastMsg);
    }
    return '${_homeLocation.displayName} konumundaki anlık hissedilen sıcaklığa ve vücut kitle indeksine '
        'göre bugün terleme dengeni koruyacak nefes alan bir iç katman tercih etmelisin. '
        'Üzerine kolayca çıkarıp giyebileceğin fermuarlı bir orta katman almanı öneririm. '
        'Dışarı çıkarken rüzgar ve sıcaklık değişimine karşı koruyucu dış katmanını yanında bulundur.';
  }

  Future<void> _addCustomRoutine() async {
    final title = _customTitleCtrl.text.trim();
    final timeStr = _customTimeCtrl.text.trim();
    if (title.isEmpty || timeStr.isEmpty) return;

    setState(() {
      _loading = true;
      _statusMessage = null;
    });
    try {
      final daysStr = _getSelectedDaysString();
      final created = await widget.routineService.createCustomRoutine(
        routineTitle: title,
        routineTime: timeStr,
        daysOfWeek: daysStr,
        leadMinutes: _selectedLeadMinutes,
      );

      final routineId = created['id'] as int;
      final notifyTime = created['notify_time']?.toString() ?? '';
      final leadMins = (created['lead_minutes'] as int?) ?? _selectedLeadMinutes;
      final commentSummary = _getCurrentSystemCommentSummary(
        created['notification_message']?.toString(),
      );

      await LocalNotificationService.instance.scheduleRoutineNotification(
        routineId: routineId,
        routineTitle: title,
        routineTimeHhMm: timeStr,
        leadMinutes: leadMins,
        systemCommentSummary: commentSummary,
      );

      final updatedList = await widget.routineService.getCustomRoutines();
      if (mounted) {
        setState(() {
          _customRoutines = updatedList;
          _statusMessage =
              '✓ "$title" ($timeStr) eklendi! $leadMins dk öncesine ($notifyTime) kişisel kombin bildirimi kuruldu.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _statusMessage = 'Rutin eklenirken hata oluştu.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleRoutineItem(Map<String, dynamic> item, bool enabled) async {
    final id = item['id'] as int;
    final title = (item['routine_title'] ?? 'Rutin').toString();
    final timeStr = (item['routine_time'] ?? '08:00').toString();
    final leadMins = (item['lead_minutes'] as int?) ?? _selectedLeadMinutes;
    final commentSummary = _getCurrentSystemCommentSummary(
      item['notification_message']?.toString(),
    );

    setState(() {
      item['is_enabled'] = enabled;
    });

    try {
      await widget.routineService.toggleCustomRoutine(
        routineId: id,
        isEnabled: enabled,
      );
      if (enabled) {
        await LocalNotificationService.instance.scheduleRoutineNotification(
          routineId: id,
          routineTitle: title,
          routineTimeHhMm: timeStr,
          leadMinutes: leadMins,
          systemCommentSummary: commentSummary,
        );
      } else {
        await LocalNotificationService.instance.cancelRoutineNotification(id);
      }
    } catch (_) {}
  }

  Future<void> _removeCustomRoutine(int id) async {
    try {
      await widget.routineService.deleteCustomRoutine(id);
      await LocalNotificationService.instance.cancelRoutineNotification(id);
      final updatedList = await widget.routineService.getCustomRoutines();
      if (mounted) {
        setState(() => _customRoutines = updatedList);
      }
    } catch (_) {}
  }

  Future<void> _getInstantOutfitForSelectedLocation() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });
    try {
      final boyVal = double.tryParse(_heightCtrl.text) ?? 175.0;
      final kiloVal = double.tryParse(_weightCtrl.text) ?? 75.0;

      await widget.routineService.updateRoutine(
        wakeUpTime: _customTimeCtrl.text.trim(),
        sehir: _homeLocation.name,
        ilce: _homeLocation.admin1,
        lat: _homeLocation.latitude,
        lon: _homeLocation.longitude,
        boy: boyVal,
        kilo: kiloVal,
        terlemeEgilimi: _sweating,
        notificationEnabled: true,
      );

      final res = await widget.routineService.getOutfitRecommendation(
        sehir: _homeLocation.displayName,
        ilce: _homeLocation.admin1,
        lat: _homeLocation.latitude,
        lon: _homeLocation.longitude,
        boy: boyVal,
        kilo: kiloVal,
        terlemeEgilimi: _sweating,
      );
      if (mounted) {
        setState(() {
          _morningBriefResult = res;
          _statusMessage = '✓ Seçilen konum ve fiziksel profiliniz için kombin önerisi hazırlandı.';
        });
      }
    } catch (_) {
      setState(() => _statusMessage = 'Kombin önerisi alınırken hata oluştu.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _testInstantNotificationSound() async {
    final summary = _getCurrentSystemCommentSummary();
    await LocalNotificationService.instance.triggerInstantRoutineTestNotification(
      systemCommentSummary: summary,
    );
    if (mounted) {
      setState(() => _statusMessage =
          '🔔 Kişisel sistem kombin yorumunun 3-4 cümlelik özetiyle bildirim anında gönderildi!');
    }
  }

  Future<void> _openProfileScreen() async {
    Navigator.of(context).pop(); // endDrawer'ı kapat
    final updatedUser = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          user: widget.user,
          authService: widget.authService,
          routineService: widget.routineService,
        ),
      ),
    );
    if (updatedUser != null && mounted) {
      widget.onUserUpdated(updatedUser);
      setState(() {
        _syncDefaultLocationFromUser(updatedUser);
      });
    }
  }

  Future<void> _openAccountSettingsScreen() async {
    Navigator.of(context).pop(); // endDrawer'ı kapat
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountSettingsScreen(
          authService: widget.authService,
          onAccountClosed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
            widget.onLogout();
          },
        ),
      ),
    );
  }

  Widget _buildQuickWeatherTab() {
    final status = _quickWeatherResult?['hava_durumu_durumu']?.toString();
    final colors = _weatherGradient(status);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: const Color(0xFF0F172A).withOpacity(0.88),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🔍 Uluslararası Hızlı Hava Durumu',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kMatteWhite),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Dünyadaki herhangi bir ülke, şehir veya ilçeyi aratarak anlık sıcaklığı, rüzgarı ve hava olayını görüntüleyin.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 14),
                  GlobalLocationAutocomplete(
                    routineService: widget.routineService,
                    initialLocation: _quickLocation,
                    labelText: 'Dünya Geneli Konum Ara',
                    onLocationSelected: (loc) => setState(() => _quickLocation = loc),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _quickLoading ? null : _searchQuickWeather,
                      icon: const Icon(Icons.search),
                      label: Text(_quickLoading ? 'Sorgulanıyor...' : 'Anlık Hava Durumunu Göster'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_quickWeatherResult != null) ...[
            const SizedBox(height: 18),
            Card(
              color: Colors.black.withOpacity(0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Text(
                      _quickWeatherResult!['sehir'].toString(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: kMatteWhite,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Chip(
                      label: Text(
                        '${_quickWeatherResult!['hava_durumu_durumu']} (WMO: ${_quickWeatherResult!['wmo_kodu']})',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${_quickWeatherResult!['sicaklik']}°C',
                      style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hissedilen: ${_quickWeatherResult!['hissedilen_sicaklik']}°C  •  Rüzgar: ${_quickWeatherResult!['ruzgar_hizi']} km/s',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTravelPackingTab() {
    final forecasts = (_travelResult?['gunluk_tahminler'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          color: const Color(0xFF0F172A),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🧳 Seyahat Valizi & Bavul Hazırlama Modu',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kMatteWhite),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Gideceğiniz uluslararası veya yerel şehri ve tarih aralığını seçin; fiziksel profilinize uygun bavul listenizi hazırlayalım.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 14),
                GlobalLocationAutocomplete(
                  routineService: widget.routineService,
                  initialLocation: _travelLocation,
                  labelText: 'Seyahat Edilecek Konum (Ülke / Şehir / İlçe)',
                  onLocationSelected: (loc) => setState(() => _travelLocation = loc),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _travelStartCtrl,
                        readOnly: true,
                        onTap: _pickTravelDateRange,
                        decoration: const InputDecoration(
                          labelText: 'Başlangıç Tarihi',
                          prefixIcon: Icon(Icons.date_range),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _travelEndCtrl,
                        readOnly: true,
                        onTap: _pickTravelDateRange,
                        decoration: const InputDecoration(
                          labelText: 'Bitiş Tarihi',
                          prefixIcon: Icon(Icons.event),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _travelLoading ? null : _generateTravelPackingList,
                    icon: const Icon(Icons.luggage),
                    label: Text(
                      _travelLoading
                          ? 'Valiz Listesi Hazırlanıyor...'
                          : 'Seyahat Valizi ve Kombin Listesi Oluştur',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_travelResult != null) ...[
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFF1E293B),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📍 ${_travelResult!['hedef_sehir']} (${_travelResult!['gun_sayisi']} Günlük Valiz Önerisi)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kMatteWhite,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _travelResult!['valiz_onerisi'].toString(),
                    style: const TextStyle(height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  const Divider(),
                  ...forecasts.map((d) {
                    final day = Map<String, dynamic>.from(d as Map);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${day['tarih']} • ${day['hava_durumu_durumu']}'),
                      trailing: Text(
                        '${day['min_sicaklik']}°C / ${day['max_sicaklik']}°C  (${day['ruzgar_hizi']} km/s)',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRoutinesAndOutfitTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. FİZİKSEL PROFİL & KOMBİN ÖNERİSİ (ANA EKRAN İLK KART)
          Card(
            color: const Color(0xFF0F172A),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '👕 Fiziksel Profil & Kombin Önerisi',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: kMatteWhite),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Varsayılan konumunuz Profilim ekranından otomatik gelir; dilerseniz aşağıdan tek seferlik başka bir konum seçip anlık öneri alabilirsiniz.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 14),
                  GlobalLocationAutocomplete(
                    routineService: widget.routineService,
                    initialLocation: _homeLocation,
                    labelText: 'Konum (Ülke / Şehir / İlçe)',
                    onLocationSelected: (loc) => setState(() => _homeLocation = loc),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _heightCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Boy (cm)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _weightCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Kilo (kg)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _getInstantOutfitForSelectedLocation,
                      icon: const Icon(Icons.checkroom),
                      label: Text(_loading ? 'Hazırlanıyor...' : 'Kombin Önerisi Al'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_morningBriefResult != null) ...[
            const SizedBox(height: 16),
            Card(
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_morningBriefResult!['sehir']} • ${_morningBriefResult!['hava_durumu_durumu']} (${_morningBriefResult!['hissedilen_sicaklik']}°C)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: kMatteWhite,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_morningBriefResult!['oneri'].toString()),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // 2. TEKİL AKILLI YÖNETİM PANELİ: "RUTİNLERİM"
          Card(
            color: const Color(0xFF0F172A),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⏰ Rutinlerim',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: kMatteWhite),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sabah uyanma, işe gidiş veya yürüyüş rutinlerinizi ekleyin. Seçtiğiniz süre kadar önce 3-4 cümlelik kişisel kombin yorumunuz sesli bildirim olarak gelir.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _customTitleCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Rutin Adı',
                            hintText: 'Örn: İşe Gidiş',
                            prefixIcon: Icon(Icons.event_note),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _customTimeCtrl,
                          readOnly: true,
                          onTap: _pickCustomRoutineTime,
                          decoration: const InputDecoration(
                            labelText: 'Saat',
                            prefixIcon: Icon(Icons.schedule),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _selectedLeadMinutes,
                    decoration: const InputDecoration(
                      labelText: 'Bildirim Ne Kadar Önce Gelsin?',
                      prefixIcon: Icon(Icons.notifications_active_outlined),
                    ),
                    items: _leadMinuteOptions
                        .map(
                          (mins) => DropdownMenuItem<int>(
                            value: mins,
                            child: Text('Rutinden $mins dakika önce'),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedLeadMinutes = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Tekrarlanacak Günler',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: ToggleButtons(
                      isSelected: _selectedDays,
                      onPressed: (index) {
                        setState(() {
                          _selectedDays[index] = !_selectedDays[index];
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      selectedColor: const Color(0xFF020617),
                      fillColor: const Color(0xFF38BDF8),
                      color: kMatteWhite,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 38),
                      children: List.generate(
                        _dayShortLabels.length,
                        (idx) => Tooltip(
                          message: _dayFullCodes[idx],
                          child: Text(
                            _dayShortLabels[idx],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _addCustomRoutine,
                      icon: const Icon(Icons.add_alarm),
                      label: const Text('Rutin Ekle'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _testInstantNotificationSound,
                      icon: const Icon(Icons.volume_up_outlined, color: Color(0xFF38BDF8)),
                      label: const Text('Bildirimi Şimdi Test Et (Kişisel Yorum Özeti)'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await LocalNotificationService.instance.showWeatherShiftAlert();
                        if (mounted) {
                          setState(() => _statusMessage =
                              '⚡ Ani hava değişimi genel uyarı bildirimi anında gönderildi!');
                        }
                      },
                      icon: const Icon(Icons.thunderstorm_outlined, color: Colors.amberAccent),
                      label: const Text('Ani Hava Değişimi Uyarısını Şimdi Test Et'),
                    ),
                  ),
                  if (_statusMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _statusMessage!,
                        style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12.5),
                      ),
                    ),
                  if (_customRoutines.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Divider(),
                    ..._customRoutines.map((item) {
                      final isEnabled = (item['is_enabled'] ?? true) == true;
                      final leadMins = item['lead_minutes'] ?? 15;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          isEnabled ? Icons.notifications_active : Icons.notifications_off_outlined,
                          color: isEnabled ? const Color(0xFF38BDF8) : Colors.white38,
                        ),
                        title: Text(
                          '${item['routine_title']} • ${item['routine_time']}',
                          style: TextStyle(
                            color: isEnabled ? kMatteWhite : Colors.white54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${item['days_of_week']}  •  $leadMins dk önce (${item['notify_time']})',
                          style: const TextStyle(fontSize: 12, color: Colors.white60),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: isEnabled,
                              onChanged: (val) => _toggleRoutineItem(item, val),
                            ),
                            IconButton(
                              tooltip: 'Rutini Sil',
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () => _removeCustomRoutine(item['id'] as int),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightSideDrawer() {
    final avatarB64 = widget.user['avatar_base64']?.toString();
    final fullName = (widget.user['full_name'] ?? 'OptiWear Kullanıcısı').toString();
    final email = (widget.user['email'] ?? '').toString();

    return Drawer(
      backgroundColor: const Color(0xFF0F172A),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: Row(
                children: [
                  buildUserAvatarWidget(avatarBase64: avatarB64, radius: 26),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          style: const TextStyle(
                            color: kMatteWhite,
                            fontWeight: FontWeight.bold,
                            fontSize: 15.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.person_outline, color: kMatteWhite),
              title: const Text('Profilim', style: TextStyle(color: kMatteWhite)),
              onTap: _openProfileScreen,
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined, color: kMatteWhite),
              title: const Text('Hesap Ayarları', style: TextStyle(color: kMatteWhite)),
              onTap: _openAccountSettingsScreen,
            ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Çıkış Yap', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.of(context).pop();
                await widget.authService.logout();
                widget.onLogout();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildRoutinesAndOutfitTab(),
      _buildTravelPackingTab(),
      _buildQuickWeatherTab(),
    ];
    final avatarB64 = widget.user['avatar_base64']?.toString();

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _buildRightSideDrawer(),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3.5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Image.asset(
                'assets/images/logo.png',
                height: 24,
                width: 24,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'OptiWear',
              style: TextStyle(
                color: kMatteWhite,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
              child: buildUserAvatarWidget(avatarBase64: avatarB64, radius: 18),
            ),
          ),
        ],
      ),
      body: pages[_selectedTabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (idx) => setState(() => _selectedTabIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checkroom),
            label: 'Kombin & Rutin',
          ),
          NavigationDestination(
            icon: Icon(Icons.luggage_outlined),
            label: 'Seyahat Valizi',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_outlined),
            label: 'Hava Durumu',
          ),
        ],
      ),
    );
  }
}

/// 1. YAN MENÜ EKRANI: PROFİLİM (Fotoğraf Seçimi, Ad Soyad, E-posta, Varsayılan Uluslararası Konum)
class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final AuthService authService;
  final RoutineService routineService;

  const ProfileScreen({
    super.key,
    required this.user,
    required this.authService,
    required this.routineService,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  String? _avatarBase64;
  late GlobalLocationSelection _defaultLocation;
  bool _saving = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: (widget.user['full_name'] ?? '').toString());
    _emailCtrl = TextEditingController(text: (widget.user['email'] ?? '').toString());
    _avatarBase64 = widget.user['avatar_base64']?.toString();

    final name = (widget.user['default_location_name'] ?? 'İstanbul').toString();
    final admin1 = (widget.user['default_admin1'] ?? '').toString();
    final country = (widget.user['default_country'] ?? 'Türkiye').toString();
    final lat = (widget.user['default_lat'] as num?)?.toDouble() ?? 41.0082;
    final lon = (widget.user['default_lon'] as num?)?.toDouble() ?? 28.9784;
    final parts = [name, if (admin1.isNotEmpty && admin1 != name) admin1, if (country.isNotEmpty) country];

    _defaultLocation = GlobalLocationSelection(
      name: name,
      admin1: admin1,
      country: country,
      latitude: lat,
      longitude: lon,
      displayName: parts.join(', '),
    );
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 360,
        maxHeight: 360,
        imageQuality: 75,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _avatarBase64 = base64Encode(bytes);
        });
      }
    } catch (_) {}
  }

  Future<void> _saveProfile() async {
    setState(() {
      _saving = true;
      _feedback = null;
    });
    try {
      final updated = await widget.authService.updateMyProfile(
        fullName: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        avatarBase64: _avatarBase64 ?? '',
        defaultLocationName: _defaultLocation.name,
        defaultAdmin1: _defaultLocation.admin1,
        defaultCountry: _defaultLocation.country,
        defaultLat: _defaultLocation.latitude,
        defaultLon: _defaultLocation.longitude,
      );
      if (mounted) {
        Navigator.of(context).pop(updated);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _feedback = 'Profil güncellenirken bir hata oluştu.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profilim', style: TextStyle(color: kMatteWhite)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Card(
          color: const Color(0xFF0F172A),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      buildUserAvatarWidget(avatarBase64: _avatarBase64, radius: 44),
                      IconButton.filled(
                        tooltip: 'Galeriden Fotoğraf Seç',
                        onPressed: _pickImageFromGallery,
                        icon: const Icon(Icons.photo_camera, size: 18),
                      ),
                    ],
                  ),
                ),
                if (_avatarBase64 != null && _avatarBase64!.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _avatarBase64 = ''),
                    child: const Text('Fotoğrafı Kaldır'),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ad Soyad',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-posta Adresi',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                GlobalLocationAutocomplete(
                  routineService: widget.routineService,
                  initialLocation: _defaultLocation,
                  labelText: 'Varsayılan Konum (Ülke / Şehir / İlçe)',
                  onLocationSelected: (loc) => setState(() => _defaultLocation = loc),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Burada kaydettiğiniz varsayılan konum, ana ekrandaki Kombin Önerisi konum alanına otomatik olarak yansır.',
                  style: TextStyle(fontSize: 11.5, color: Colors.white60),
                ),
                if (_feedback != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_feedback!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _saveProfile,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Kaydediliyor...' : 'Profili ve Varsayılan Konumu Kaydet'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 2. YAN MENÜ EKRANI: HESAP AYARLARI (Hesabı Dondur & Hesabı Kalıcı Sil - KVKK)
class AccountSettingsScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onAccountClosed;

  const AccountSettingsScreen({
    super.key,
    required this.authService,
    required this.onAccountClosed,
  });

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  Future<void> _confirmAction({required bool permanentDelete}) async {
    final passCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(permanentDelete ? 'Hesabı Kalıcı Sil (KVKK)' : 'Hesabı Dondur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              permanentDelete
                  ? 'Tüm kişisel verileriniz ve hesabınız veritabanından kalıcı olarak silinecektir.'
                  : 'Hesabınız pasife alınacak (is_active=false) ve açık oturumlarınız kapatılacaktır.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mevcut Şifreniz'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: permanentDelete ? Colors.red : Colors.orange,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(permanentDelete ? 'Kalıcı Olarak Sil' : 'Dondur'),
          ),
        ],
      ),
    );

    if (confirmed == true && passCtrl.text.isNotEmpty) {
      try {
        if (permanentDelete) {
          await widget.authService.deleteAccount(password: passCtrl.text);
        } else {
          await widget.authService.freezeAccount(password: passCtrl.text);
        }
        widget.onAccountClosed();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Şifre doğrulanamadı veya işlem başarısız.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hesap Ayarları', style: TextStyle(color: kMatteWhite)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          color: const Color(0xFF0F172A),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Hesap Güvenliği ve Veri Yönetimi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kMatteWhite),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hesabınızı geçici olarak dondurabilir veya KVKK kapsamında tüm verilerinizle birlikte kalıcı olarak silebilirsiniz.',
                  style: TextStyle(fontSize: 12.5, color: Colors.white70),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  icon: const Icon(Icons.pause_circle_outline, color: Colors.orangeAccent),
                  label: const Text('Hesabı Dondur (Geçici Pasife Al)'),
                  onPressed: () => _confirmAction(permanentDelete: false),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  label: const Text('Hesabı Kalıcı Sil (KVKK)'),
                  onPressed: () => _confirmAction(permanentDelete: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
