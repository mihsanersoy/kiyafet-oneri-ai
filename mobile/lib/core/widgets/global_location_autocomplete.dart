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

  factory GlobalLocationSelection.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] ?? 'İstanbul').toString();
    final admin1 = (json['admin1'] ?? '').toString();
    final country = (json['country'] ?? '').toString();
    final disp = (json['display_name'] ?? name).toString();
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

/// 300ms Debounced Uluslararası Konum Arama ve Seçim Bileşeni
/// Statik liste gömmeden doğrudan GET /locations/search?q=<arama> uç noktasını sorgular.
class GlobalLocationAutocomplete extends StatefulWidget {
  final RoutineService routineService;
  final GlobalLocationSelection initialLocation;
  final String labelText;
  final ValueChanged<GlobalLocationSelection> onLocationSelected;

  const GlobalLocationAutocomplete({
    super.key,
    required this.routineService,
    required this.initialLocation,
    this.labelText = 'Konum Ara (Ülke / Şehir / İlçe)',
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
    _debounce = Timer(const Duration(milliseconds: 300), () async {
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
            hintText: 'Örn: Kadıköy, Londra, Tokyo, Kaş...',
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
            constraints: const BoxConstraints(maxHeight: 210),
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
                    '${item.latitude.toStringAsFixed(2)}, ${item.longitude.toStringAsFixed(2)}',
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
