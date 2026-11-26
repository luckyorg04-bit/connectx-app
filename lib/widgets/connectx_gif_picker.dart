import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// A GIF returned by Openverse. The original file remains linked to its
/// creator and license so the attribution can travel with the chat message.
class ConnectXGif {
  final String id;
  final String title;
  final String url;
  final String thumbnail;
  final String attribution;
  final String creator;
  final String license;
  final String sourceUrl;

  const ConnectXGif({
    required this.id,
    required this.title,
    required this.url,
    required this.thumbnail,
    required this.attribution,
    required this.creator,
    required this.license,
    required this.sourceUrl,
  });

  factory ConnectXGif.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] ?? 'GIF').toString().trim();
    final creator = (json['creator'] ?? 'Unknown creator').toString().trim();
    final license = (json['license'] ?? 'Creative Commons').toString().trim();
    final attribution = (json['attribution'] ??
        '"$title" by $creator is marked with $license.').toString();
    return ConnectXGif(
      id: (json['id'] ?? json['url'] ?? title).toString(),
      title: title.isEmpty ? 'GIF' : title,
      url: (json['url'] ?? '').toString(),
      thumbnail: (json['thumbnail'] ?? json['url'] ?? '').toString(),
      attribution: attribution,
      creator: creator,
      license: license,
      sourceUrl: (json['foreign_landing_url'] ?? json['detail_url'] ?? '').toString(),
    );
  }
}

class ConnectXGifPicker extends StatefulWidget {
  const ConnectXGifPicker({super.key});

  static Future<ConnectXGif?> show(BuildContext context) {
    return showModalBottomSheet<ConnectXGif>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ConnectXGifPicker(),
    );
  }

  @override
  State<ConnectXGifPicker> createState() => _ConnectXGifPickerState();
}

class _ConnectXGifPickerState extends State<ConnectXGifPicker> {
  static const _categories = <String, String>{
    'Trending': 'funny reaction',
    'Funny': 'funny reaction meme',
    'Love': 'love heart animated',
    'Sad': 'sad crying reaction',
    'Celebration': 'celebration party congratulations',
    'Dance': 'dance animated',
    'Reactions': 'reaction face',
  };

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ConnectXGif> _items = [];
  String _selectedCategory = 'Trending';
  bool _loading = true;
  bool _searchMode = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCuratedCollection();
  }

  Future<List<ConnectXGif>> _search(String query) async {
    final uri = Uri.https('api.openverse.org', '/v1/images/', {
      'q': query,
      'extension': 'gif',
      'license_type': 'commercial',
      'mature': 'false',
      'page': '1',
      'page_size': '20',
    });
    final response = await http.get(uri, headers: {
      'Accept': 'application/json',
      'User-Agent': 'ConnectX-Chat/1.1 (GIF picker)',
    }).timeout(const Duration(seconds: 18));
    if (response.statusCode != 200) {
      throw Exception('GIF catalogue returned ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (decoded['results'] as List? ?? const []);
    return results
        .whereType<Map>()
        .map((item) => ConnectXGif.fromJson(Map<String, dynamic>.from(item)))
        .where((gif) => gif.url.startsWith('https://') &&
            gif.url.toLowerCase().split('?').first.endsWith('.gif'))
        .toList();
  }

  Future<void> _loadCuratedCollection() async {
    setState(() {
      _loading = true;
      _error = null;
      _searchMode = false;
      _selectedCategory = 'Trending';
    });
    try {
      // Six independently curated searches provide a 100+ item starter library.
      final queries = _categories.entries.toList();
      final responses = await Future.wait(
        queries.map((entry) => _search(entry.value)),
      );
      final unique = <String, ConnectXGif>{};
      for (var i = 0; i < responses.length; i++) {
        for (final gif in responses[i]) {
          unique.putIfAbsent(gif.id, () => gif);
        }
      }
      if (!mounted) return;
      setState(() {
        _items = unique.values.toList();
        _loading = false;
        if (_items.isEmpty) _error = 'No GIFs found. Try Search.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'GIFs could not load. Check your internet and tap Retry.';
      });
    }
  }

  Future<void> _loadCategory(String category) async {
    setState(() {
      _selectedCategory = category;
      _loading = true;
      _error = null;
      _searchMode = false;
    });
    try {
      final items = await _search(_categories[category]!);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        if (items.isEmpty) _error = 'No GIFs in this category. Try another.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this category. Tap Retry.';
      });
    }
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      await _loadCuratedCollection();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _searchMode = true;
    });
    try {
      final items = await _search(query);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        if (items.isEmpty) _error = 'No GIFs found for "$query".';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Search failed. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF111B21) : Colors.white;
    final foreground = dark ? const Color(0xFFE9edef) : const Color(0xFF111B21);
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * .84,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 15, 12, 10),
              child: Row(
                children: [
                  Expanded(child: Text('GIFs',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: foreground))),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: foreground),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  hintText: 'Search GIFs',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    onPressed: _runSearch,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  filled: true,
                  fillColor: dark ? const Color(0xFF202C33) : const Color(0xFFF0F2F5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _categories.keys.map((category) {
                  final selected = !_searchMode && _selectedCategory == category;
                  return Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text(category),
                      selected: selected,
                      onSelected: (_) => _loadCategory(category),
                    ),
                  );
                }).toList(),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.gif_box_outlined, size: 42),
                            const SizedBox(height: 10),
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton(onPressed: _searchMode ? _runSearch : _loadCuratedCollection,
                              child: const Text('Retry')),
                          ]),
                        ))
                      : GridView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 9,
                            mainAxisSpacing: 9,
                            childAspectRatio: 1.22,
                          ),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final gif = _items[index];
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => Navigator.pop(context, gif),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(gif.thumbnail, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: dark ? const Color(0xFF26343C) : const Color(0xFFE8ECEF),
                                        child: const Icon(Icons.gif, size: 42),
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(7),
                                        color: Colors.black.withOpacity(.62),
                                        child: Text(gif.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white, fontSize: 11)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text('GIFs from Openverse · Creative Commons / public-domain media',
                style: TextStyle(color: foreground.withOpacity(.58), fontSize: 10)),
            ),
          ],
        ),
      ),
    );
  }
}
