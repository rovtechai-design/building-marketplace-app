import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http; // ? ADDED
import 'services/api_client.dart';
import 'services/auth_service.dart';

final authService = AuthService();
final apiClient = ApiClient(authService: authService);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  print('FIREBASE INIT OK');
  runApp(const MarketplaceApp());
}

/* -----------------------------
   DATA MODEL + IN-MEMORY STORE
-------------------------------- */

class Listing {
  final String id;
  final String title;
  final String description;
  final double price;
  final DateTime createdAt;

  Listing({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.createdAt,
  });
}

class ListingsStore extends ChangeNotifier {
  final List<Listing> _items = [
    Listing(
      id: '1',
      title: 'Desk lamp',
      description: 'Works perfectly. Pickup only.',
      price: 8.0,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
    Listing(
      id: '2',
      title: 'Kettle',
      description: 'Used for 2 months. Clean.',
      price: 12.0,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  List<Listing> get items => List.unmodifiable(_items);

  void add(Listing listing) {
    _items.insert(0, listing);
    notifyListeners();
  }
}

class BuildingOption {
  final int id;
  final String name;

  const BuildingOption({
    required this.id,
    required this.name,
  });
}

/* -----------------------------
   APP SHELL
-------------------------------- */

class MarketplaceApp extends StatelessWidget {
  const MarketplaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Building Marketplace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

/* -----------------------------
   LOGIN
-------------------------------- */

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final email = _email.text.trim();
    final pass = _password.text;

    if (email.isEmpty || pass.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Enter email and password.';
      });
      return;
    }

    try {
      await authService.signInWithEmailPassword(email, pass);
      if (!mounted) return;
      setState(() => _loading = false);

      final store = ListingsStore();

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BuildingGateScreen(userEmail: email, store: store),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Building Marketplace',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text('Sign in to continue',
                  style: TextStyle(color: Theme.of(context).hintColor)),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* -----------------------------
   BUILDING GATE
-------------------------------- */

class BuildingGateScreen extends StatefulWidget {
  final String userEmail;
  final ListingsStore store;

  const BuildingGateScreen({
    super.key,
    required this.userEmail,
    required this.store,
  });

  @override
  State<BuildingGateScreen> createState() => _BuildingGateScreenState();
}

class _BuildingGateScreenState extends State<BuildingGateScreen> {
  final _inviteCode = TextEditingController();

  bool _loading = true;
  bool _joining = false;
  String? _error;
  List<BuildingOption> _buildings = const [];

  @override
  void initState() {
    super.initState();
    _fetchBuildings();
  }

  @override
  void dispose() {
    _inviteCode.dispose();
    super.dispose();
  }

  Future<void> _fetchBuildings() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await apiClient.get('/my-buildings');
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw StateError('Failed to load buildings: ${res.body}');
      }
      final buildings = _parseBuildings(res.body);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _buildings = buildings;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _joinBuilding() async {
    final inviteCode = _inviteCode.text.trim();
    if (inviteCode.isEmpty) {
      setState(() => _error = 'Enter an invite code.');
      return;
    }

    setState(() {
      _joining = true;
      _error = null;
    });

    try {
      final res = await apiClient.postJson(
        '/join-building',
        {'invite_code': inviteCode},
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw StateError('Failed to join building: ${res.body}');
      }
      _inviteCode.clear();
      if (!mounted) return;
      setState(() => _joining = false);
      await _fetchBuildings();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = e.toString();
      });
    }
  }

  List<BuildingOption> _parseBuildings(String body) {
    final decoded = jsonDecode(body);
    final items = <dynamic>[];

    if (decoded is List) {
      items.addAll(decoded);
    } else if (decoded is Map<String, dynamic>) {
      final candidates = [
        decoded['buildings'],
        decoded['data'],
        decoded['items'],
      ];

      for (final candidate in candidates) {
        if (candidate is List) {
          items.addAll(candidate);
          break;
        }
      }

      if (items.isEmpty) {
        final count = decoded['count'];
        if (count is num && count == 0) {
          return const [];
        }
      }
    }

    return items.map(_parseBuildingOption).whereType<BuildingOption>().toList();
  }

  BuildingOption? _parseBuildingOption(dynamic item) {
    if (item is! Map) return null;

    final rawId = item['id'] ?? item['building_id'] ?? item['buildingId'];
    final id = rawId is int ? rawId : int.tryParse('$rawId');
    if (id == null) return null;

    final rawName = item['name'] ?? item['building_name'] ?? item['buildingName'];
    final name = rawName == null || '$rawName'.trim().isEmpty
        ? 'Building $id'
        : '$rawName';

    return BuildingOption(id: id, name: name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Buildings')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildings.isEmpty
                  ? JoinBuildingScreen(
                      inviteCodeController: _inviteCode,
                      loading: _joining,
                      error: _error,
                      onJoin: _joinBuilding,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null)
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        Expanded(
                          child: ListView.separated(
                            itemCount: _buildings.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, index) {
                              final building = _buildings[index];
                              return ListTile(
                                title: Text(building.name),
                                onTap: () {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => ListingsFeedScreen(
                                        userEmail: widget.userEmail,
                                        store: widget.store,
                                        buildingId: building.id,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}

class JoinBuildingScreen extends StatelessWidget {
  final TextEditingController inviteCodeController;
  final bool loading;
  final String? error;
  final Future<void> Function() onJoin;

  const JoinBuildingScreen({
    super.key,
    required this.inviteCodeController,
    required this.loading,
    required this.error,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Join a building',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: inviteCodeController,
          decoration: const InputDecoration(
            labelText: 'Invite code',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: loading ? null : () => onJoin(),
          child: loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Join'),
        ),
      ],
    );
  }
}

/* -----------------------------
   LISTINGS FEED
-------------------------------- */

class ListingsFeedScreen extends StatefulWidget {
  final String userEmail;
  final ListingsStore store;
  final int buildingId;

  const ListingsFeedScreen({
    super.key,
    required this.userEmail,
    required this.store,
    required this.buildingId,
  });

  @override
  State<ListingsFeedScreen> createState() => _ListingsFeedScreenState();
}

class _ListingsFeedScreenState extends State<ListingsFeedScreen> {
  // ✅ ADDED: Health probe
  Future<void> probeHealth() async {
    try {
      final url = Uri.parse('http://localhost:8000/health');
      final res = await http.get(url);
      // ignore: avoid_print
      print('HEALTH => ${res.statusCode} | ${res.body}');
    } catch (e) {
      // ignore: avoid_print
      print('HEALTH ERROR => $e');
    }
  }

  Future<void> fetchListings() async {
    print('FETCH LISTINGS CALLED');
    try {
      final res = await apiClient.get(
        '/listings',
        query: {'building_id': widget.buildingId.toString()},
      );
      print('LISTINGS STATUS => ${res.statusCode}');
      print('LISTINGS BODY => ${res.body}');
    } catch (e) {
      print('LISTINGS ERROR => $e');
    }
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);

    // ✅ ADDED: call probe on screen load
    probeHealth();
    fetchListings();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<Listing>(
      MaterialPageRoute(builder: (_) => const CreateListingScreen()),
    );

    if (created != null) {
      widget.store.add(created);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing created')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.store.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Listings'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            icon: const Icon(Icons.logout),
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Signed in as: ${widget.userEmail}',
                  style: TextStyle(color: Theme.of(context).hintColor)),
              const SizedBox(height: 12),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('No listings yet. Create one.'))
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final it = items[i];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(it.title,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  Text(it.description),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('£${it.price.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      Text(_timeAgo(it.createdAt),
                                          style: TextStyle(
                                              color:
                                                  Theme.of(context).hintColor)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        label: const Text('New listing'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

/* -----------------------------
   CREATE LISTING FORM
-------------------------------- */

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();

  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _error = null);

    final title = _title.text.trim();
    final desc = _desc.text.trim();
    final priceText = _price.text.trim();

    if (title.isEmpty || desc.isEmpty || priceText.isEmpty) {
      setState(() => _error = 'Fill all fields.');
      return;
    }

    final price = double.tryParse(priceText);
    if (price == null || price < 0) {
      setState(() => _error = 'Enter a valid price.');
      return;
    }

    final listing = Listing(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      description: desc,
      price: price,
      createdAt: DateTime.now(),
    );

    Navigator.of(context).pop(listing);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create listing')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _desc,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Price (GBP)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('Create'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

