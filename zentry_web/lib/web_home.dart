import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import './web_api_service.dart';
import './web_login.dart';

const Color _navy = Color(0xFF17263D);
const Color _pageBackground = Color(0xFFF4F6FA);
const Color _mutedText = Color(0xFF65748B);
const Color _borderColor = Color(0xFFE4E9F1);
const Color _green = Color(0xFF168568);
const Color _red = Color(0xFFD94848);
const Color _blue = Color(0xFF3478C8);
const Color _amber = Color(0xFFD97706);
const Color _purple = Color(0xFF7C5BB5);

class WebHome extends StatefulWidget {
  const WebHome({super.key});

  @override
  State<WebHome> createState() => _WebHomeState();
}

class _WebHomeState extends State<WebHome> {
  static const String api = WebApiService.baseUrl;

  Timer? _timer;
  bool _busy = false;
  bool _loading = true;
  bool _sidebarExpanded = true;

  String? _error;
  String _selectedPage = 'Dashboard';
  String _selectedFilter = 'HELP REQUESTED';

  Map<String, dynamic>? _incident;
  Map<String, dynamic> _summary = {};
  List<dynamic> _responses = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out of Zentry?'),
        content: const Text(
          'You will need to log in again to access safety operations.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('LOG OUT'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    _timer?.cancel();
    WebApiService.logout();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WebLogin()),
      (route) => false,
    );
  }

  Future<void> _refresh() async {
    if (_busy) return;
    _busy = true;

    try {
      final response = await http
          .get(
            Uri.parse('$api/incidents/active'),
            headers: WebApiService.authHeaders,
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw Exception('Incident request failed: ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw Exception('Unexpected incident response.');
      }

      Map<String, dynamic>? active;

      if (decoded.isNotEmpty) {
        active = Map<String, dynamic>.from(decoded.first);
      }

      Map<String, dynamic> summary = {};
      List<dynamic> responses = [];

      if (active != null) {
        final id = active['id'];

        final results = await Future.wait([
          http
              .get(
                Uri.parse('$api/incidents/$id/summary'),
                headers: WebApiService.authHeaders,
              )
              .timeout(const Duration(seconds: 12)),
          http
              .get(
                Uri.parse('$api/incidents/$id/responses'),
                headers: WebApiService.authHeaders,
              )
              .timeout(const Duration(seconds: 12)),
        ]);

        if (results[0].statusCode == 200) {
          final data = jsonDecode(results[0].body);
          if (data is Map) {
            summary = Map<String, dynamic>.from(data);
          }
        }

        if (results[1].statusCode == 200) {
          final data = jsonDecode(results[1].body);
          if (data is List) {
            responses = data;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _incident = active;
        _summary = summary;
        _responses = responses;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString().contains('log in')
            ? 'Your session may have expired. Please log in again.'
            : 'Cannot connect to the Zentry API. Check that the backend is running.';
        _loading = false;
      });
    } finally {
      _busy = false;
    }
  }

  Future<void> _startIncident() async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      final response = await http
          .post(
            Uri.parse('$api/incidents'),
            headers: WebApiService.authHeaders,
            body: jsonEncode({
              'title': 'Fire Alarm',
              'message': 'Evacuate now - North Car Parking',
              'location': 'Mumbai Office - Floor 3',
              'created_by': 'Suresh',
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        _showMessage('Incident #${data['id']} created.');
      } else if (response.statusCode == 409) {
        _showMessage('An incident is already active.');
      } else {
        _showMessage('Could not start incident (${response.statusCode}).');
      }
    } catch (_) {
      if (mounted) _showMessage('Cannot connect to the Zentry API.');
    } finally {
      _busy = false;
      await _refresh();
    }
  }

  Future<void> _clearIncident() async {
    final incident = _incident;
    if (incident == null || _busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Issue All Clear?'),
        content: const Text(
          'Confirm that the incident has been assessed and that it is '
          'appropriate to mark it cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _green),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('CONFIRM ALL CLEAR'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);

    try {
      final response = await http
          .post(
            Uri.parse('$api/incidents/${incident['id']}/clear'),
            headers: WebApiService.authHeaders,
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200) {
        _showMessage('Incident marked as cleared.');
      } else {
        _showMessage('Unable to clear incident (${response.statusCode}).');
      }
    } catch (_) {
      if (mounted) _showMessage('Cannot connect to the Zentry API.');
    } finally {
      _busy = false;
      await _refresh();
    }
  }

  Future<void> _showCreateEmployeeDialog() async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateEmployeeDialog(),
    );

    if (result != null && mounted) {
      _showMessage(result);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  int _count(String key) {
    final value = _summary[key];
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  int _statusCount(String status) {
    return _responses.where((item) {
      if (item is! Map) return false;
      return '${item['response_status']}' == status;
    }).length;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'SAFE_AT_ASSEMBLY':
        return 'AT ASSEMBLY';
      case 'SAFE_OUTSIDE':
        return 'SAFE OUTSIDE';
      case 'SAFE_INSIDE':
        return 'SAFE INSIDE';
      case 'NEED_HELP':
        return 'HELP REQUESTED';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'SAFE_AT_ASSEMBLY':
        return _green;
      case 'SAFE_OUTSIDE':
        return _blue;
      case 'SAFE_INSIDE':
        return _amber;
      case 'NEED_HELP':
        return _red;
      default:
        return _mutedText;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'SAFE_AT_ASSEMBLY':
        return Icons.check_circle_outline;
      case 'SAFE_OUTSIDE':
        return Icons.location_on_outlined;
      case 'SAFE_INSIDE':
        return Icons.warning_amber_rounded;
      case 'NEED_HELP':
        return Icons.sos_rounded;
      default:
        return Icons.person_outline;
    }
  }

  String _time(dynamic value) {
    if (value == null) return 'Time unavailable';

    final date = DateTime.tryParse(value.toString())?.toLocal();
    if (date == null) return 'Time unavailable';

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _responseTimestamp(Map<String, dynamic> item) {
    final value =
        item['created_at'] ??
        item['responded_at'] ??
        item['updated_at'] ??
        item['timestamp'];

    return _time(value);
  }

  List<dynamic> get _filteredResponses {
    final statusForFilter = {
      'HELP REQUESTED': 'NEED_HELP',
      'SAFE INSIDE': 'SAFE_INSIDE',
      'AT ASSEMBLY': 'SAFE_AT_ASSEMBLY',
      'SAFE OUTSIDE': 'SAFE_OUTSIDE',
    };

    if (_selectedFilter == 'ALL RESPONSES') {
      return _responses;
    }

    if (_selectedFilter == 'EXPECTED' || _selectedFilter == 'NO RESPONSE') {
      // The current responses endpoint only returns submitted responses.
      // A complete expected/no-response list needs an employee roster API.
      return _responses.where((item) {
        if (item is! Map) return false;
        final status = '${item['response_status'] ?? ''}';
        return status.isEmpty || status == 'NO_RESPONSE';
      }).toList();
    }

    final status = statusForFilter[_selectedFilter];
    if (status == null) return _responses;

    return _responses.where((item) {
      if (item is! Map) return false;
      return '${item['response_status'] ?? ''}' == status;
    }).toList();
  }

  int _filterCount(String filter) {
    switch (filter) {
      case 'HELP REQUESTED':
        return _count('help_requested') != 0
            ? _count('help_requested')
            : _statusCount('NEED_HELP');
      case 'SAFE INSIDE':
        return _statusCount('SAFE_INSIDE');
      case 'AT ASSEMBLY':
        return _count('at_assembly') != 0
            ? _count('at_assembly')
            : _statusCount('SAFE_AT_ASSEMBLY');
      case 'SAFE OUTSIDE':
        return _statusCount('SAFE_OUTSIDE');
      case 'NO RESPONSE':
        return _count('no_response');
      case 'EXPECTED':
        return _count('expected');
      default:
        return _responses.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 950;

    return Scaffold(
      backgroundColor: _pageBackground,
      body: SafeArea(
        child: Row(
          children: [
            if (isWide || _sidebarExpanded) _buildSidebar(isWide: isWide),
            Expanded(
              child: Column(
                children: [
                  _buildTopBar(isWide: isWide),
                  if (_error != null) _buildErrorBanner(),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
                            onRefresh: _refresh,
                            child: _buildCurrentPage(),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar({required bool isWide}) {
    final expanded = isWide ? _sidebarExpanded : true;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: expanded ? 248 : 76,
      color: _navy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 20 : 12,
              vertical: 22,
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Image.asset(
                    'assets/images/zentry_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ZENTRY',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'SAFETY OPERATIONS',
                          style: TextStyle(
                            color: Color(0xFFB9C7D9),
                            fontSize: 9,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Divider(color: Color(0xFF35445A), height: 1),
          ),
          const SizedBox(height: 18),
          _navItem(
            title: 'Dashboard',
            icon: Icons.grid_view_rounded,
            expanded: expanded,
          ),
          _navItem(
            title: 'Employees',
            icon: Icons.groups_2_outlined,
            expanded: expanded,
          ),
          _navItem(
            title: 'Visitors',
            icon: Icons.badge_outlined,
            expanded: expanded,
          ),
          _navItem(
            title: 'Incidents',
            icon: Icons.emergency_outlined,
            expanded: expanded,
          ),
          _navItem(
            title: 'Requires Action',
            icon: Icons.fact_check_outlined,
            expanded: expanded,
            badge: _count('help_requested'),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: Colors.white.withValues(alpha: 0.15)),
          ),
          if (expanded)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                'SAFETY MANAGEMENT PORTAL',
                style: TextStyle(
                  color: Color(0xFF9AAAC0),
                  fontSize: 9,
                  letterSpacing: 1,
                ),
              ),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.logout_rounded, color: Colors.white70),
            title: expanded
                ? const Text('Log out', style: TextStyle(color: Colors.white70))
                : null,
            onTap: _logout,
            horizontalTitleGap: 10,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _navItem({
    required String title,
    required IconData icon,
    required bool expanded,
    int? badge,
  }) {
    final selected = _selectedPage == title;

    return Padding(
      padding: EdgeInsets.fromLTRB(expanded ? 12 : 8, 3, expanded ? 12 : 8, 3),
      child: Tooltip(
        message: expanded ? '' : title,
        child: Material(
          color: selected ? const Color(0xFF31425C) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                _selectedPage = title;
                if (!MediaQuery.sizeOf(context).width.isFinite) return;
                if (MediaQuery.sizeOf(context).width < 950) {
                  _sidebarExpanded = false;
                }
              });
            },
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: expanded ? 12 : 10,
                vertical: 13,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: selected ? Colors.white : const Color(0xFFC5D0DF),
                    size: 21,
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : const Color(0xFFD6DFEA),
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (badge != null && badge > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$badge',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar({required bool isWide}) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Toggle sidebar',
            onPressed: () {
              setState(() => _sidebarExpanded = !_sidebarExpanded);
            },
            icon: const Icon(Icons.menu_rounded, color: _navy),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _selectedPage,
              style: const TextStyle(
                color: _navy,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isWide)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined, color: _mutedText, size: 18),
                  SizedBox(width: 5),
                  Text(
                    'Mumbai Office',
                    style: TextStyle(color: _mutedText, fontSize: 12),
                  ),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _showCreateEmployeeDialog,
            icon: const Icon(Icons.person_add_alt_1, size: 17),
            label: const Text('Add Employee'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _navy,
              side: const BorderSide(color: _borderColor),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Refresh dashboard',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, color: _mutedText),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: const Color(0xFFFFF1E6),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFF874B00), fontSize: 12),
            ),
          ),
          TextButton(onPressed: _refresh, child: const Text('RETRY')),
        ],
      ),
    );
  }

  Widget _buildCurrentPage() {
    switch (_selectedPage) {
      case 'Dashboard':
        return _buildDashboard();
      case 'Requires Action':
        return _buildRequiresActionPage();
      case 'Incidents':
        return _buildIncidentsPage();
      case 'Employees':
        return _buildManagementPlaceholder(
          title: 'Employee Management',
          subtitle: 'Create and manage employee access to Zentry.',
          icon: Icons.groups_2_outlined,
          details: const [
            'Create employee accounts',
            'Review employee safety responses during an incident',
            'Employee activation, editing and password management require additional backend endpoints',
          ],
          actionLabel: 'Add Employee',
          onAction: _showCreateEmployeeDialog,
        );
      case 'Visitors':
        return _buildManagementPlaceholder(
          title: 'Visitor Management',
          subtitle: 'Visitor access and emergency readiness.',
          icon: Icons.badge_outlined,
          details: const [
            'Visitor records and VRF IDs',
            'Email OTP verification',
            'Automatic visitor account expiry',
            'These features will connect to the visitor API when implemented',
          ],
        );
      default:
        return _buildDashboard();
    }
  }

  Widget _buildDashboard() {
    final active = _incident != null;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Safety overview',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Monitor personnel safety and incident response in real time.',
                    style: TextStyle(color: _mutedText, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _systemStatusPill(active),
          ],
        ),
        const SizedBox(height: 22),
        _buildIncidentBanner(active),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1200
                ? 6
                : constraints.maxWidth >= 800
                ? 3
                : constraints.maxWidth >= 500
                ? 2
                : 1;

            return GridView.count(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: columns == 1 ? 4.0 : 1.35,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _statCard(
                  title: 'Expected',
                  count: _count('expected'),
                  icon: Icons.groups_outlined,
                  color: const Color(0xFF53657D),
                  filter: 'EXPECTED',
                ),
                _statCard(
                  title: 'At Assembly',
                  count: _count('at_assembly'),
                  icon: Icons.check_circle_outline,
                  color: _green,
                  filter: 'AT ASSEMBLY',
                ),
                _statCard(
                  title: 'Safe Outside',
                  count: _statusCount('SAFE_OUTSIDE') != 0
                      ? _statusCount('SAFE_OUTSIDE')
                      : _count('safe_elsewhere'),
                  icon: Icons.location_on_outlined,
                  color: _blue,
                  filter: 'SAFE OUTSIDE',
                ),
                _statCard(
                  title: 'Safe Inside',
                  count: _statusCount('SAFE_INSIDE'),
                  icon: Icons.warning_amber_rounded,
                  color: _amber,
                  filter: 'SAFE INSIDE',
                ),
                _statCard(
                  title: 'Help Requested',
                  count: _count('help_requested') != 0
                      ? _count('help_requested')
                      : _statusCount('NEED_HELP'),
                  icon: Icons.sos_rounded,
                  color: _red,
                  filter: 'HELP REQUESTED',
                ),
                _statCard(
                  title: 'No Response',
                  count: _count('no_response'),
                  icon: Icons.schedule_rounded,
                  color: _purple,
                  filter: 'NO RESPONSE',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 850) {
              return Column(
                children: [
                  _buildRequiresActionCard(),
                  const SizedBox(height: 18),
                  _buildIncidentDetailsCard(),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: _buildRequiresActionCard()),
                const SizedBox(width: 18),
                Expanded(flex: 4, child: _buildIncidentDetailsCard()),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const Text(
          'Dashboard data refreshes automatically every 4 seconds.',
          style: TextStyle(color: _mutedText, fontSize: 11),
        ),
      ],
    );
  }

  Widget _systemStatusPill(bool active) {
    final color = active ? _red : _green;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            active ? 'INCIDENT ACTIVE' : 'NO ACTIVE INCIDENT',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentBanner(bool active) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFFFF1F0) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? const Color(0xFFF4C7C4) : _borderColor,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: active ? const Color(0xFFFBDAD7) : const Color(0xFFE8F5EF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              active ? Icons.campaign_rounded : Icons.shield_outlined,
              color: active ? _red : _green,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active
                      ? 'INCIDENT #${_incident!['id']} · ${_incident!['title'] ?? 'Active incident'}'
                      : 'Your site is not reporting an active incident',
                  style: const TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  active
                      ? '${_incident!['message'] ?? ''} · ${_incident!['location'] ?? 'Location not specified'}'
                      : 'Start an incident when emergency coordination is required.',
                  style: const TextStyle(color: _mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (active)
            FilledButton.icon(
              onPressed: _busy ? null : _clearIncident,
              icon: const Icon(Icons.verified_outlined, size: 17),
              label: const Text('Issue All Clear'),
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
              ),
            )
          else
            FilledButton.icon(
              onPressed: _busy ? null : _startIncident,
              icon: const Icon(Icons.add_alert_rounded, size: 17),
              label: const Text('Start Incident'),
              style: FilledButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _statCard({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required String filter,
  }) {
    final selected = _selectedFilter == filter;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedFilter = filter;
            _selectedPage = 'Requires Action';
          });
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color : _borderColor,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: _mutedText,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(icon, color: color, size: 20),
                ],
              ),
              Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              Text(
                'View people  →',
                style: TextStyle(
                  color: selected ? color : _mutedText,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildRequiresActionCard() {
    final filters = [
      'HELP REQUESTED',
      'SAFE INSIDE',
      'NO RESPONSE',
      'EXPECTED',
      'AT ASSEMBLY',
      'SAFE OUTSIDE',
      'ALL RESPONSES',
    ];

    return _panel(
      title: 'Requires Action',
      trailing: Text(
        '${_filteredResponses.length} shown',
        style: const TextStyle(color: _mutedText, fontSize: 11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: filters.map((filter) {
              final selected = _selectedFilter == filter;
              final count = _filterCount(filter);

              return ChoiceChip(
                label: Text('$filter ($count)'),
                selected: selected,
                onSelected: (_) {
                  setState(() => _selectedFilter = filter);
                },
                selectedColor: const Color(0xFFE6EDF7),
                backgroundColor: const Color(0xFFF7F8FB),
                labelStyle: TextStyle(
                  color: selected ? _navy : _mutedText,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 10,
                ),
                side: BorderSide(
                  color: selected ? const Color(0xFFB9CBE2) : _borderColor,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                showCheckmark: false,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: _borderColor),
          const SizedBox(height: 6),
          if (_filteredResponses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      _selectedFilter == 'HELP REQUESTED'
                          ? Icons.health_and_safety_outlined
                          : Icons.people_outline_rounded,
                      size: 36,
                      color: _mutedText.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _selectedFilter == 'NO RESPONSE' ||
                              _selectedFilter == 'EXPECTED'
                          ? 'A complete people roster is needed for this list.'
                          : 'No records for this status yet.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _mutedText, fontSize: 12),
                    ),
                    if (_selectedFilter == 'NO RESPONSE' ||
                        _selectedFilter == 'EXPECTED')
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Text(
                          'The current API returns submitted responses only.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _mutedText, fontSize: 10),
                        ),
                      ),
                  ],
                ),
              ),
            )
          else
            ..._filteredResponses.take(30).map((raw) {
              final item = Map<String, dynamic>.from(raw as Map);
              return _responseRow(item);
            }),
        ],
      ),
    );
  }

  Widget _responseRow(Map<String, dynamic> item) {
    final status = '${item['response_status'] ?? ''}';
    final color = _statusColor(status);
    final name =
        item['employee_name'] ??
        item['full_name'] ??
        item['visitor_name'] ??
        item['name'] ??
        'Person';
    final message = item['message']?.toString() ?? '';
    final location = item['location']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_statusIcon(status), color: color, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name',
                  style: const TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                        if (location.isNotEmpty) location,
                        if (message.isNotEmpty) message,
                      ].join(' · ').isEmpty
                      ? 'No additional details supplied'
                      : [
                          if (location.isNotEmpty) location,
                          if (message.isNotEmpty) message,
                        ].join(' · '),
                  style: const TextStyle(color: _mutedText, fontSize: 11),
                ),
                const SizedBox(height: 5),
                Text(
                  _responseTimestamp(item),
                  style: const TextStyle(color: _mutedText, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              _statusLabel(status),
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentDetailsCard() {
    final active = _incident != null;

    return _panel(
      title: 'Incident details',
      trailing: Icon(
        active ? Icons.warning_amber_rounded : Icons.shield_outlined,
        color: active ? _red : _green,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailLine(
            'Current status',
            active ? 'Incident active' : 'No active incident',
            valueColor: active ? _red : _green,
          ),
          _detailLine('Incident ID', active ? '#${_incident!['id']}' : '—'),
          _detailLine(
            'Incident title',
            active ? '${_incident!['title'] ?? 'Untitled'}' : '—',
          ),
          _detailLine(
            'Created by',
            active ? '${_incident!['created_by'] ?? 'Not supplied'}' : '—',
          ),
          _detailLine('People responded', '${_count('responded')}'),
          _detailLine(
            'Help requests',
            '${_count('help_requested')}',
            valueColor: _red,
          ),
          if (active)
            _detailLine('Incident created', _time(_incident!['created_at'])),
          const SizedBox(height: 14),
          const Divider(color: _borderColor),
          const SizedBox(height: 8),
          const Text(
            'Verify personnel safety and coordinate assistance before issuing '
            'an all-clear. This dashboard does not replace emergency procedures.',
            style: TextStyle(color: _mutedText, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value, {Color valueColor = _navy}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: _mutedText, fontSize: 11),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequiresActionPage() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Requires Action',
          style: TextStyle(
            color: _navy,
            fontSize: 25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Review reported statuses and identify people who may need assistance.',
          style: TextStyle(color: _mutedText, fontSize: 13),
        ),
        const SizedBox(height: 20),
        _buildRequiresActionCard(),
      ],
    );
  }

  Widget _buildIncidentsPage() {
    final active = _incident != null;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Incident Management',
          style: TextStyle(
            color: _navy,
            fontSize: 25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Control the current incident and review its response information.',
          style: TextStyle(color: _mutedText, fontSize: 13),
        ),
        const SizedBox(height: 20),
        _buildIncidentBanner(active),
        const SizedBox(height: 18),
        _buildIncidentDetailsCard(),
        const SizedBox(height: 18),
        _buildRequiresActionCard(),
      ],
    );
  }

  Widget _buildManagementPlaceholder({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<String> details,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _navy,
            fontSize: 25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: _mutedText, fontSize: 13)),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0F8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _navy, size: 28),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This section is being prepared. The existing working API '
                'features remain available while additional management '
                'endpoints are implemented.',
                style: TextStyle(color: _mutedText, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 18),
              ...details.map(
                (detail) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: _green,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          detail,
                          style: const TextStyle(color: _navy, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(actionLabel),
                  style: FilledButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CreateEmployeeDialog extends StatefulWidget {
  const _CreateEmployeeDialog();

  @override
  State<_CreateEmployeeDialog> createState() => _CreateEmployeeDialogState();
}

class _CreateEmployeeDialogState extends State<_CreateEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _employeeCodeController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  bool _saving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _employeeCodeController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _createEmployee() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse('${WebApiService.baseUrl}/auth/officers/employees'),
            headers: WebApiService.authHeaders,
            body: jsonEncode({
              'employee_code': _employeeCodeController.text.trim(),
              'full_name': _nameController.text.trim(),
              'email': _emailController.text.trim().toLowerCase(),
            }),
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // Keep a readable fallback message if the response is not JSON.
      }

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        Navigator.of(
          context,
        ).pop(data['message']?.toString() ?? 'Employee created successfully.');
      } else {
        setState(() {
          _errorMessage =
              data['detail']?.toString() ??
              'Employee creation failed (${response.statusCode}).';
        });
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Cannot connect to the server. Check the backend and try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Add Employee',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Enter the employee details to create their account.',
                    style: TextStyle(color: _mutedText, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _employeeCodeController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Employee ID',
                    hintText: 'e.g. EMP001',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter employee ID';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nameController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().length < 2) {
                      return 'Enter the employee name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailController,
                  enabled: !_saving,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Company email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch(email)) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: _red, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: _saving ? null : _createEmployee,
          style: FilledButton.styleFrom(
            backgroundColor: _navy,
            foregroundColor: Colors.white,
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('CREATE EMPLOYEE'),
        ),
      ],
    );
  }
}
