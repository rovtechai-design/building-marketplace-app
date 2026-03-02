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
   LOGIN (DUMMY)
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
          builder: (_) => ListingsFeedScreen(userEmail: email, store: store),
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
   LISTINGS FEED
-------------------------------- */

class ListingsFeedScreen extends StatefulWidget {
  final String userEmail;
  final ListingsStore store;

  const ListingsFeedScreen({
    super.key,
    required this.userEmail,
    required this.store,
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
        query: {'building_id': '1'},
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

