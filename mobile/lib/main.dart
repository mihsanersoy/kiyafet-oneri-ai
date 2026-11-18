import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'core/background/weather_alert_worker.dart';
import 'core/constants/turkiye_locations.dart';
import 'core/network/api_client.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/storage/secure_storage_service.dart';
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
                  onLogout: () => setState(() => _currentUser = null),
                ),
    );
  }
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
                    Text(
                      'OptiWear',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: kMatteWhite,
                            letterSpacing: 0.4,
                          ),
                    ),
                    const SizedBox(height: 4),
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
  final VoidCallback onLogout;

  const RoutineDashboardScreen({
    super.key,
    required this.user,
    required this.authService,
    required this.routineService,
    required this.onLogout,
  });

  @override
  State<RoutineDashboardScreen> createState() => _RoutineDashboardScreenState();
}

class _RoutineDashboardScreenState extends State<RoutineDashboardScreen> {
  int _selectedTabIndex = 0;

  // Sekme 1: Hızlı Hava Durumu Arama (81 İl & İlçe Combobox)
  String _quickSelectedCity = 'Ankara';
  String _quickSelectedDistrict = 'Merkez';
  Map<String, dynamic>? _quickWeatherResult;
  bool _quickLoading = false;

  // Sekme 2: Seyahat / Bavul Hazırlama Modu (81 İl & İlçe Combobox)
  String _travelSelectedCity = 'Antalya';
  String _travelSelectedDistrict = 'Kaş';
  final _travelStartCtrl = TextEditingController(text: '2026-11-20');
  final _travelEndCtrl = TextEditingController(text: '2026-11-24');
  Map<String, dynamic>? _travelResult;
  bool _travelLoading = false;

  // Sekme 3: Birleştirilmiş "Rutinlerim" Paneli + Fiziksel Profil
  final _customTitleCtrl = TextEditingController(text: 'Sabah Uyanma');
  final _customTimeCtrl = TextEditingController(text: '07:30');
  static const List<String> _dayShortLabels = ['P', 'S', 'Ç', 'P', 'C', 'C', 'P'];
  static const List<String> _dayFullCodes = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
  final List<bool> _selectedDays = [true, true, true, true, true, false, false];
  List<Map<String, dynamic>> _customRoutines = [];

  String _profileSelectedCity = 'İstanbul';
  String _profileSelectedDistrict = 'Merkez';
  final _heightCtrl = TextEditingController(text: '175');
  final _weightCtrl = TextEditingController(text: '75');
  String _sweating = 'Hayır';

  bool _loading = false;
  String? _statusMessage;
  Map<String, dynamic>? _morningBriefResult;

  @override
  void initState() {
    super.initState();
    _loadAllRoutines();
  }

  Future<void> _loadAllRoutines() async {
    try {
      final r = await widget.routineService.getMyRoutine();
      final customList = await widget.routineService.getCustomRoutines();
      if (!mounted) return;
      final savedCity = (r['sehir'] ?? 'İstanbul').toString();
      final resolvedCity = TurkiyeLocations.iller.contains(savedCity) ? savedCity : 'İstanbul';
      final districtList = TurkiyeLocations.getIlceler(resolvedCity);
      final savedDist = (r['ilce'] ?? '').toString();
      final resolvedDist = districtList.contains(savedDist) ? savedDist : districtList.first;

      setState(() {
        _profileSelectedCity = resolvedCity;
        _profileSelectedDistrict = resolvedDist;
        _heightCtrl.text = (r['boy'] ?? 175).toString();
        _weightCtrl.text = (r['kilo'] ?? 75).toString();
        _sweating = (r['terleme_egilimi'] ?? 'Hayır').toString();
        _customRoutines = customList;
      });
      await WeatherAlertWorker.initializeAndSchedule(
        city: _profileSelectedCity,
        district: _profileSelectedDistrict == 'Merkez' ? '' : _profileSelectedDistrict,
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

  Widget _buildCityDistrictSelectors({
    required String selectedCity,
    required String selectedDistrict,
    required ValueChanged<String> onCityChanged,
    required ValueChanged<String> onDistrictChanged,
  }) {
    final districts = TurkiyeLocations.getIlceler(selectedCity);
    final validDistrict =
        districts.contains(selectedDistrict) ? selectedDistrict : districts.first;

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: selectedCity,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'İl Seçin',
              prefixIcon: Icon(Icons.location_city),
            ),
            items: TurkiyeLocations.iller
                .map((city) => DropdownMenuItem(
                      value: city,
                      child: Text(city, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) onCityChanged(val);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: validDistrict,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'İlçe Seçin',
              prefixIcon: Icon(Icons.place_outlined),
            ),
            items: districts
                .map((dist) => DropdownMenuItem(
                      value: dist,
                      child: Text(dist, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) onDistrictChanged(val);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _searchQuickWeather() async {
    setState(() => _quickLoading = true);
    try {
      final res = await widget.routineService.fetchQuickWeather(
        sehir: _quickSelectedCity,
        ilce: _quickSelectedDistrict == 'Merkez' ? '' : _quickSelectedDistrict,
      );
      if (mounted) setState(() => _quickWeatherResult = res);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Şehir hava durumu alınamadı.')),
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
        hedefSehir: _travelSelectedCity,
        hedefIlce: _travelSelectedDistrict == 'Merkez' ? '' : _travelSelectedDistrict,
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
      );

      final routineId = created['id'] as int;
      final notifyTime = created['notify_time']?.toString() ?? '';

      await LocalNotificationService.instance.scheduleRoutineBefore10Min(
        routineId: routineId,
        routineTitle: title,
        routineTimeHhMm: timeStr,
      );

      final updatedList = await widget.routineService.getCustomRoutines();
      if (mounted) {
        setState(() {
          _customRoutines = updatedList;
          _statusMessage =
              '✓ "$title" ($timeStr) eklendi! 10 dk öncesine ($notifyTime) sesli bildirim kuruldu.';
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

    setState(() {
      item['is_enabled'] = enabled;
    });

    try {
      await widget.routineService.toggleCustomRoutine(
        routineId: id,
        isEnabled: enabled,
      );
      if (enabled) {
        await LocalNotificationService.instance.scheduleRoutineBefore10Min(
          routineId: id,
          routineTitle: title,
          routineTimeHhMm: timeStr,
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

  Future<void> _saveProfileAndGetOutfit() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });
    try {
      await widget.routineService.updateRoutine(
        wakeUpTime: _customTimeCtrl.text.trim(),
        sehir: _profileSelectedCity,
        ilce: _profileSelectedDistrict == 'Merkez' ? '' : _profileSelectedDistrict,
        boy: double.tryParse(_heightCtrl.text) ?? 175.0,
        kilo: double.tryParse(_weightCtrl.text) ?? 75.0,
        terlemeEgilimi: _sweating,
        notificationEnabled: true,
      );
      await WeatherAlertWorker.initializeAndSchedule(
        city: _profileSelectedCity,
        district: _profileSelectedDistrict == 'Merkez' ? '' : _profileSelectedDistrict,
      );
      final res = await widget.routineService.triggerMorningBrief();
      if (mounted) {
        setState(() {
          _morningBriefResult = res;
          _statusMessage = '✓ Profiliniz güncellendi ve kombin öneriniz hazırlandı.';
        });
      }
    } catch (_) {
      setState(() => _statusMessage = 'Kombin önerisi alınırken hata oluştu.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 0 Saniye Gecikmeyle Anında Bildirim ve Özel Ses Testi
  Future<void> _testInstantNotificationSound() async {
    await LocalNotificationService.instance.triggerInstantRoutineTestNotification();
    if (mounted) {
      setState(() => _statusMessage =
          '🔔 Bildirim ve özel ses efekti 0 saniye gecikmeyle anında tetiklendi!');
    }
  }

  Future<void> _confirmAccountAction({required bool permanentDelete}) async {
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
        widget.onLogout();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Şifre doğrulanamadı veya işlem başarısız.')),
          );
        }
      }
    }
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
                    '🔍 Hızlı Şehir Hava Durumu',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kMatteWhite),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '81 ilden şehrinizi ve ilçenizi seçerek anlık sıcaklığı, rüzgarı ve hava olayını görüntüleyin.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 14),
                  _buildCityDistrictSelectors(
                    selectedCity: _quickSelectedCity,
                    selectedDistrict: _quickSelectedDistrict,
                    onCityChanged: (city) => setState(() {
                      _quickSelectedCity = city;
                      _quickSelectedDistrict = TurkiyeLocations.getIlceler(city).first;
                    }),
                    onDistrictChanged: (dist) => setState(() => _quickSelectedDistrict = dist),
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
                  'Gideceğiniz şehri ve tarih aralığını seçin; fiziksel profilinize uygun bavul ve kombin listenizi hazırlayalım.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 14),
                _buildCityDistrictSelectors(
                  selectedCity: _travelSelectedCity,
                  selectedDistrict: _travelSelectedDistrict,
                  onCityChanged: (city) => setState(() {
                    _travelSelectedCity = city;
                    _travelSelectedDistrict = TurkiyeLocations.getIlceler(city).first;
                  }),
                  onDistrictChanged: (dist) => setState(() => _travelSelectedDistrict = dist),
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

  Widget _buildRoutinesAndAccountTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // TEKİL AKILLI YÖNETİM PANELİ: "RUTİNLERİM"
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
                    'Sabah uyanma, işe gidiş veya yürüyüş rutinlerinizi ekleyin. Rutin saatinden 10 dk önce sesli uyarı çalar.',
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
                      label: const Text('Bildirimi Şimdi Test Et'),
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
                          '${item['days_of_week']}  •  Uyarı: ${item['notify_time']}',
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
          const SizedBox(height: 16),

          // FİZİKSEL PROFİL & ANLIK KOMBİN KARTI (ŞEHİR/İLÇE COMBOBOX İLE)
          Card(
            color: const Color(0xFF0F172A),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '👕 Fiziksel Profil & Kombin Önerisi',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kMatteWhite),
                  ),
                  const SizedBox(height: 14),
                  _buildCityDistrictSelectors(
                    selectedCity: _profileSelectedCity,
                    selectedDistrict: _profileSelectedDistrict,
                    onCityChanged: (city) => setState(() {
                      _profileSelectedCity = city;
                      _profileSelectedDistrict = TurkiyeLocations.getIlceler(city).first;
                    }),
                    onDistrictChanged: (dist) => setState(() => _profileSelectedDistrict = dist),
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
                      onPressed: _loading ? null : _saveProfileAndGetOutfit,
                      icon: const Icon(Icons.checkroom),
                      label: Text(_loading ? 'Hazırlanıyor...' : 'Profili Kaydet ve Kombinimi Üret'),
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
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.pause_circle_outline, color: Colors.orangeAccent),
                  label: const Text('Hesabı Dondur'),
                  onPressed: () => _confirmAccountAction(permanentDelete: false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  label: const Text('Hesabı Sil (KVKK)'),
                  onPressed: () => _confirmAccountAction(permanentDelete: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildQuickWeatherTab(),
      _buildTravelPackingTab(),
      _buildRoutinesAndAccountTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'OptiWear • ${widget.user['full_name'] ?? ''}',
          style: const TextStyle(color: kMatteWhite, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'Çıkış Yap',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await widget.authService.logout();
              widget.onLogout();
            },
          ),
        ],
      ),
      body: pages[_selectedTabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (idx) => setState(() => _selectedTabIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.travel_explore),
            label: 'Hızlı Hava',
          ),
          NavigationDestination(
            icon: Icon(Icons.luggage_outlined),
            label: 'Seyahat Valizi',
          ),
          NavigationDestination(
            icon: Icon(Icons.alarm),
            label: 'Rutinlerim',
          ),
        ],
      ),
    );
  }
}
