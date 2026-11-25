import 'dart:async';
import 'package:flutter/material.dart';
import '../../features/routine/routine_service.dart';

class GlobalLocationSelection {
  final String name;
  final String admin1;
  final String country;
  final double latitude;
  final double longitude;
  final String displayName;

  const GlobalLocationSelection({
    required this.name,
    this.admin1 = '',
    this.country = '',
    required this.latitude,
    required this.longitude,
    required this.displayName,
  });

  /// Veritabanı ve öneri istekleri için sehir = admin1 (Örn: Samsun)
  String get sehir => admin1.trim().isNotEmpty ? admin1.trim() : name.trim();

  /// Veritabanı ve öneri istekleri için ilce = name (Örn: Tekkeköy)
  String get ilce {
    final n = name.trim();
    final a = admin1.trim();
    if (a.isNotEmpty && n.toLowerCase() != a.toLowerCase()) {
      return n;
    }
    return '';
  }

  factory GlobalLocationSelection.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] ?? 'İstanbul').toString().trim();
    final admin1 = (json['admin1'] ?? '').toString().trim();
    final country = (json['country'] ?? '').toString().trim();
    final parts = <String>[];
    for (final p in [name, admin1, country]) {
      if (p.isNotEmpty && (parts.isEmpty || parts.last.toLowerCase() != p.toLowerCase())) {
        parts.add(p);
      }
    }
    final disp = (json['display_name'] ?? parts.join(', ')).toString();
    return GlobalLocationSelection(
      name: name,
      admin1: admin1,
      country: country,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 41.0082,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 28.9784,
      displayName: disp,
    );
  }
}

/// Akıllı İlçe & Şehir Arama Seçim Kutusu (GET /locations/search?q=<arama>)
class GlobalLocationAutocomplete extends StatefulWidget {
  final RoutineService routineService;
  final GlobalLocationSelection initialLocation;
  final String labelText;
  final ValueChanged<GlobalLocationSelection> onLocationSelected;

  const GlobalLocationAutocomplete({
    super.key,
    required this.routineService,
    required this.initialLocation,
    this.labelText = 'İlçe veya Şehir Ara (Örn: Tekkeköy, Samsun)',
    required this.onLocationSelected,
  });

  @override
  State<GlobalLocationAutocomplete> createState() => _GlobalLocationAutocompleteState();
}

class _GlobalLocationAutocompleteState extends State<GlobalLocationAutocomplete> {
  late final TextEditingController _controller;
  Timer? _debounce;
  bool _searching = false;
  List<GlobalLocationSelection> _results = [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialLocation.displayName);
  }

  @override
  void didUpdateWidget(covariant GlobalLocationAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLocation.displayName != widget.initialLocation.displayName &&
        _results.isEmpty) {
      _controller.text = widget.initialLocation.displayName;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String val) {
    _debounce?.cancel();
    final q = val.trim();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      try {
        final rawList = await widget.routineService.searchGlobalLocations(q);
        if (!mounted) return;
        setState(() {
          _results = rawList.map(GlobalLocationSelection.fromJson).toList();
          _searching = false;
        });
      } catch (_) {
        if (mounted) {
          setState(() {
            _results = [];
            _searching = false;
          });
        }
      }
    });
  }

  void _selectItem(GlobalLocationSelection item) {
    _debounce?.cancel();
    setState(() {
      _controller.text = item.displayName;
      _results = [];
      _searching = false;
    });
    FocusScope.of(context).unfocus();
    widget.onLocationSelected(item);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          onChanged: _onQueryChanged,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: 'İlçe veya Şehir Ara (Örn: Tekkeköy, Samsun)',
            prefixIcon: const Icon(Icons.public),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (_controller.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Temizle',
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _results = []);
                        },
                      )
                    : null),
          ),
        ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, idx) {
                final item = _results[idx];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined, color: Color(0xFF38BDF8), size: 20),
                  title: Text(
                    item.displayName,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    item.ilce.isNotEmpty
                        ? 'İlçe: ${item.ilce} • İl/Bölge: ${item.sehir}'
                        : 'Şehir/Bölge: ${item.sehir}',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  onTap: () => _selectItem(item),
                );
              },
            ),
          ),
      ],
    );
  }
}
