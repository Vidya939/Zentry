import 'dart:async';

import 'package:flutter/material.dart';

import 'web_api_service.dart';
import 'web_login.dart';

class WebHome extends StatefulWidget {
  const WebHome({super.key});

  @override
  State<WebHome> createState() => _WebHomeState();
}

class _WebHomeState extends State<WebHome> {
  Timer? _timer;

  String _page = 'Dashboard';
  bool _sidebarCollapsed = false;
  bool _loading = false;
  String? _error;
  String? _notice;

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _incident;
  Map<String, dynamic> _summary = {};
  // Map<String, dynamic> _peopleData = {};

  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _visitors = [];
  List<Map<String, dynamic>> _incidents = [];
  List<Map<String, dynamic>> _people = [];

  DateTime? _fromDate;
  DateTime? _toDate;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _peopleSearchController = TextEditingController();

  final ScrollController _peopleVerticalController = ScrollController();
  final ScrollController _peopleHorizontalController = ScrollController();

  String _peopleFilter = 'ALL';
  @override
  void initState() {
    super.initState();
    _loadInitial();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _page == 'Dashboard') {
        _refreshIncident(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchController.dispose();
    _peopleSearchController.dispose();
    _peopleVerticalController.dispose();
    _peopleHorizontalController.dispose();
    super.dispose();
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _string(dynamic value, [String fallback = '—']) {
    if (value == null || value.toString().trim().isEmpty) return fallback;
    return value.toString();
  }

  bool _active(dynamic value) {
    return value == true || value == 1 || value.toString() == '1';
  }

  String _date(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return '—';
    }

    final parsed = DateTime.tryParse(value.toString().trim());

    if (parsed == null) {
      return value.toString();
    }

    // API timestamps with +05:30 or Z already contain timezone information.
    // Do not add another timezone offset.
    final ist =
        parsed.isUtc || value.toString().contains(RegExp(r'[+-]\d{2}:\d{2}$'))
        ? parsed.toUtc().add(const Duration(hours: 5, minutes: 30))
        : parsed;

    String twoDigits(int number) => number.toString().padLeft(2, '0');

    return '${twoDigits(ist.day)}/${twoDigits(ist.month)}/${ist.year} '
        '${twoDigits(ist.hour)}:${twoDigits(ist.minute)} IST';
  }

  String _dateOnly(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${value.year}';
  }

  int? _currentIncidentId() {
    final value = _incident?['id'];
    if (value == null) return null;
    return _intValue(value);
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await WebApiService.getOfficerProfile();
      if (!mounted) return;
      setState(() => _profile = profile);

      await _refreshIncident(silent: true);
      await _loadEmployees();
      await _loadVisitors();
      await _loadIncidents();
    } catch (e) {
      if (mounted) setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });

    try {
      await action();
      if (mounted && successMessage != null) {
        setState(() => _notice = successMessage);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshIncident({bool silent = false}) async {
    try {
      final active = await WebApiService.getActiveIncidents();
      if (!mounted) return;

      if (active.isEmpty) {
        setState(() {
          _incident = null;
          _summary = {};
          // _peopleData = {};
          _people = [];
        });
        return;
      }

      final incident = active.first;
      final id = _intValue(incident['id']);

      final results = await Future.wait([
        WebApiService.getIncidentSummary(id),
        WebApiService.getIncidentPeople(id),
      ]);

      if (!mounted) return;

      final peopleData = Map<String, dynamic>.from(results[1] as Map);
      final rawPeople = peopleData['people'];

      setState(() {
        _incident = incident;
        _summary = Map<String, dynamic>.from(results[0] as Map);
        // _peopleData = peopleData;
        _people = rawPeople is List
            ? rawPeople
                  .whereType<Map>()
                  .map((p) => Map<String, dynamic>.from(p))
                  .toList()
            : [];
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() => _error = _cleanError(e));
    }
  }

  Future<void> _loadEmployees() async {
    final result = await WebApiService.getEmployees();
    if (mounted) setState(() => _employees = result);
  }

  Future<void> _loadVisitors() async {
    final result = await WebApiService.getVisitors();
    if (mounted) setState(() => _visitors = result);
  }

  Future<void> _loadIncidents() async {
    final result = await WebApiService.getIncidents(
      fromDate: _fromDate,
      toDate: _toDate,
    );
    if (mounted) setState(() => _incidents = result);
  }

  Future<void> _reloadCurrentPage() async {
    await _runAction(() async {
      switch (_page) {
        case 'Employees':
          await _loadEmployees();
          break;
        case 'Visitors':
          await _loadVisitors();
          break;
        case 'Incidents':
          await _loadIncidents();
          break;
        case 'Dashboard':
          await _refreshIncident();
          break;
        case 'Requires Action':
          await _refreshIncident();
          break;
      }
    });
  }

  Future<void> _createIncidentDialog() async {
    String selectedType = 'Fire';
    String selectedLocation = 'Admin Block';

    final message = TextEditingController(
      text: 'EVACUATE NOW IMMEDIATELY. Proceed to North Car Parking.',
    );

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Start emergency incident'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Emergency type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Fire', child: Text('Fire')),
                        DropdownMenuItem(value: 'Smoke', child: Text('Smoke')),
                        DropdownMenuItem(
                          value: 'Gas Leakage',
                          child: Text('Gas Leakage'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            selectedType = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      value: selectedLocation,
                      decoration: const InputDecoration(
                        labelText: 'Incident location',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Admin Block',
                          child: Text('Admin Block'),
                        ),
                        DropdownMenuItem(
                          value: 'North Block',
                          child: Text('North Block'),
                        ),
                        DropdownMenuItem(
                          value: 'Conf Room',
                          child: Text('Conf Room'),
                        ),
                        DropdownMenuItem(
                          value: 'North Block Canteen',
                          child: Text('North Block Canteen'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            selectedLocation = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE5E5),
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'EVACUATE NOW IMMEDIATELY',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.groups, color: Colors.blue),
                      title: Text('Assembly point'),
                      subtitle: Text('North Car Parking'),
                    ),

                    TextField(
                      controller: message,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Emergency instructions',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Start incident'),
              ),
            ],
          ),
        ),
      );

      if (confirmed != true || !mounted) return;

      await _runAction(() async {
        await WebApiService.createIncident(
          title: selectedType,
          message: message.text,
          location: selectedLocation,
        );

        await _refreshIncident();
        await _loadIncidents();
      }, successMessage: 'Incident started.');
    } finally {
      message.dispose();
    }
  }

  Future<void> _clearIncidentDialog() async {
    final id = _currentIncidentId();
    if (id == null) return;

    final safeConfirmed = _intValue(_summary['safe_confirmed']);
    final expected = _intValue(_summary['expected']);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm All Clear'),
        content: Text(
          'Safe confirmations: $safeConfirmed of $expected.\n\n'
          'Only issue All Clear after confirming that the emergency is resolved '
          'and everyone is safely accounted for.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Request All Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _runAction(() async {
      await WebApiService.clearIncident(id);
      await _refreshIncident();
      await _loadIncidents();
    }, successMessage: 'Incident cleared successfully.');
  }

  Future<void> _dispatchPerson(Map<String, dynamic> person) async {
    final incidentId = _currentIncidentId();
    if (incidentId == null) return;

    final type = _string(person['account_type'], 'employee');
    final personId = _intValue(person['person_id']);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dispatch warden'),
        content: Text(
          'Record a warden dispatch for ${_string(person['name'])} '
          '(${_string(person['identifier'])})?\n\n'
          'This records the dispatch. It does not mark the person safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm dispatch'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    await _runAction(() async {
      await WebApiService.dispatchWarden(
        incidentId: incidentId,
        accountType: type,
        personId: personId,
      );
      await _refreshIncident();
    }, successMessage: 'Warden dispatch recorded.');
  }

  Future<void> _markLocated(Map<String, dynamic> person) async {
    final incidentId = _currentIncidentId();
    if (incidentId == null) return;

    final type = _string(person['account_type'], 'employee');
    final personId = _intValue(person['person_id']);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark person as located'),
        content: Text(
          'Mark ${_string(person['name'])} as located?\n\n'
          'This action records that the person was located. Their '
          'emergency status will not be changed and All Clear will '
          'still require a safe status confirmation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Mark located'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    await _runAction(() async {
      await WebApiService.markLocated(
        incidentId: incidentId,
        accountType: type,
        personId: personId,
      );
      await _refreshIncident();
    }, successMessage: 'Person marked as located, not as safe.');
  }

  Future<void> _editProfileDialog() async {
    final name = TextEditingController(
      text: _string(_profile?['full_name'], ''),
    );
    final location = TextEditingController(
      text: _string(_profile?['location'], ''),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Officer profile'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: TextEditingController(
                  text: _string(_profile?['email'], ''),
                ),
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Registered email',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: location,
                decoration: const InputDecoration(
                  labelText: 'Office / location',
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Role: ${_string(_profile?['role'])}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save profile'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _runAction(() async {
      _profile = await WebApiService.updateOfficerProfile(
        fullName: name.text,
        location: location.text,
      );
      await WebApiService.getOfficerProfile().then((value) {
        _profile = value;
      });
    }, successMessage: 'Officer profile updated.');
  }

  Future<void> _employeeDialog({Map<String, dynamic>? employee}) async {
    final editing = employee != null;
    final code = TextEditingController(
      text: _string(employee?['employee_code'], ''),
    );
    final name = TextEditingController(
      text: _string(employee?['full_name'], ''),
    );
    final email = TextEditingController(text: _string(employee?['email'], ''));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(editing ? 'Edit employee' : 'Add employee'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                decoration: const InputDecoration(labelText: 'Employee ID'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Company email'),
              ),
              if (!editing) ...[
                const SizedBox(height: 12),
                const Text(
                  'A temporary password will be emailed to the employee. '
                  'They must change it on first login.',
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(editing ? 'Save changes' : 'Create employee'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _runAction(
      () async {
        if (editing) {
          await WebApiService.updateEmployee(
            id: _intValue(employee['id']),
            employeeCode: code.text,
            fullName: name.text,
            email: email.text,
          );
        } else {
          await WebApiService.createEmployee(
            employeeCode: code.text,
            fullName: name.text,
            email: email.text,
          );
        }
        await _loadEmployees();
      },
      successMessage: editing
          ? 'Employee details updated.'
          : 'Employee created. Check the employee email delivery.',
    );
  }

  Future<void> _setEmployeeActive(Map<String, dynamic> employee) async {
    final currentlyActive = _active(employee['is_active']);
    final activate = !currentlyActive;

    final confirmed = await _confirm(
      title: activate ? 'Activate employee' : 'Deactivate employee',
      message:
          'Are you sure you want to ${activate ? 'activate' : 'deactivate'} '
          '${_string(employee['full_name'])}?',
      action: activate ? 'Activate' : 'Deactivate',
    );

    if (!confirmed) return;

    await _runAction(() async {
      await WebApiService.setEmployeeStatus(
        id: _intValue(employee['id']),
        isActive: activate,
      );
      await _loadEmployees();
      await _refreshIncident();
    }, successMessage: 'Employee status updated.');
  }

  Future<void> _setVisitorActive(Map<String, dynamic> visitor) async {
    final currentlyActive = _active(visitor['is_active']);
    final activate = !currentlyActive;

    if (activate) {
      final rawExpiry = visitor['expires_at']?.toString() ?? '';
      final parsedExpiry = DateTime.tryParse(rawExpiry);

      final expiry = parsedExpiry == null
          ? null
          : (rawExpiry.endsWith('Z') ||
                RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(rawExpiry))
          ? parsedExpiry.toUtc().add(const Duration(hours: 5, minutes: 30))
          : parsedExpiry;

      if (visitor['email_verified'] != true ||
          expiry == null ||
          !expiry.isAfter(
            DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)),
          )) {
        _showMessage(
          'This visitor cannot be activated because their access has '
          'expired or their email is not verified. They must sign in '
          'again to renew their nine-hour access.',
        );
        return;
      }
    }

    final confirmed = await _confirm(
      title: activate ? 'Activate visitor' : 'Deactivate visitor',
      message:
          'Are you sure you want to ${activate ? 'activate' : 'deactivate'} '
          '${_string(visitor['full_name'])}?',
      action: activate ? 'Activate' : 'Deactivate',
    );

    if (!confirmed) return;

    await _runAction(() async {
      await WebApiService.setVisitorStatus(
        id: _intValue(visitor['id']),
        isActive: activate,
      );
      await _loadVisitors();
      await _refreshIncident();
    }, successMessage: 'Visitor status updated.');
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickDate({required bool from}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: (from ? _fromDate : _toDate) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (selected == null || !mounted) return;

    setState(() {
      if (from) {
        _fromDate = selected;
      } else {
        _toDate = selected;
      }
    });
  }

  Future<void> _applyIncidentFilters() async {
    if (_fromDate != null && _toDate != null && _fromDate!.isAfter(_toDate!)) {
      setState(() => _error = 'From date must be on or before To date.');
      return;
    }

    await _runAction(() async {
      await _loadIncidents();
    });
  }

  Future<void> _logout() async {
    final confirmed = await _confirm(
      title: 'Log out',
      message: 'Do you want to log out of the Zentry officer dashboard?',
      action: 'Log out',
    );

    if (!confirmed || !mounted) return;

    await WebApiService.logout();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WebLogin()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                if (_error != null) _messageBanner(_error!, isError: true),
                if (_notice != null) _messageBanner(_notice!, isError: false),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _buildPage(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectSidebarPage(String page) {
    setState(() {
      _page = page;
      _error = null;
      _notice = null;
    });

    switch (page) {
      case 'Employees':
        _loadEmployees();
        break;
      case 'Visitors':
        _loadVisitors();
        break;
      case 'Incidents':
        _loadIncidents();
        break;
      case 'Requires Action':
        _refreshIncident();
        break;
      case 'Dashboard':
        _refreshIncident(silent: true);
        break;
    }
  }

  Widget _sidebarLogo() {
    return Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Image.asset('assets/images/zentry_logo.png', fit: BoxFit.contain),
    );
  }

  Widget _buildSidebar() {
    const items = [
      ('Dashboard', Icons.dashboard_outlined),
      ('Employees', Icons.people_outline),
      ('Visitors', Icons.badge_outlined),
      ('Incidents', Icons.history),
      ('Requires Action', Icons.warning_amber_outlined),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: _sidebarCollapsed ? 76 : 230,
      color: const Color(0xFF14243A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _sidebarCollapsed ? 16 : 18,
              vertical: 22,
            ),
            child: _sidebarCollapsed
                ? Center(child: _sidebarLogo())
                : Row(
                    children: [
                      _sidebarLogo(),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'ZENTRY',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 21,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),

          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 12),
          for (final item in items)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _sidebarCollapsed ? 8 : 10,
                vertical: 3,
              ),
              child: Tooltip(
                message: _sidebarCollapsed ? item.$1 : '',
                child: _sidebarCollapsed
                    ? InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _selectSidebarPage(item.$1),
                        child: Container(
                          height: 46,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: _page == item.$1
                                ? const Color(0xFF2C4260)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Icon(
                              item.$2,
                              color: Colors.white70,
                              size: 22,
                            ),
                          ),
                        ),
                      )
                    : ListTile(
                        dense: true,
                        minTileHeight: 46,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        selected: _page == item.$1,
                        selectedTileColor: const Color(0xFF2C4260),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        leading: Icon(item.$2, color: Colors.white70, size: 22),
                        title: Text(
                          item.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
                        onTap: () => _selectSidebarPage(item.$1),
                      ),
              ),
            ),
          const Spacer(),
          const Divider(color: Colors.white24, height: 1),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _sidebarCollapsed ? 8 : 10,
              vertical: 8,
            ),
            child: Tooltip(
              message: _sidebarCollapsed ? 'Logout' : '',
              child: _sidebarCollapsed
                  ? InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _logout,
                      child: const SizedBox(
                        height: 46,
                        width: double.infinity,
                        child: Center(
                          child: Icon(
                            Icons.logout,
                            color: Colors.white70,
                            size: 22,
                          ),
                        ),
                      ),
                    )
                  : ListTile(
                      dense: true,
                      minTileHeight: 46,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      leading: const Icon(
                        Icons.logout,
                        color: Colors.white70,
                        size: 22,
                      ),
                      title: const Text(
                        'Logout',
                        style: TextStyle(color: Colors.white),
                      ),
                      onTap: _logout,
                    ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _sidebarCollapsed = !_sidebarCollapsed;
              });
            },
            icon: const Icon(Icons.menu_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _page,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _editProfileDialog,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    child: Icon(Icons.person_outline, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _string(_profile?['full_name'], 'Safety Officer'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${_string(_profile?['role'])} · '
                        '${_string(_profile?['location'], 'Location not set')}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_outlined, size: 15),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageBanner(String message, {required bool isError}) {
    return Container(
      width: double.infinity,
      color: isError ? const Color(0xFFFFE7E7) : const Color(0xFFE4F7E9),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? Colors.red.shade800 : Colors.green.shade800,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          IconButton(
            onPressed: () => setState(() {
              _error = null;
              _notice = null;
            }),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildPage() {
    switch (_page) {
      case 'Employees':
        return _buildEmployeesPage();
      case 'Visitors':
        return _buildVisitorsPage();
      case 'Incidents':
        return _buildIncidentsPage();
      case 'Requires Action':
        return _buildActionPage();
      default:
        return _buildDashboardPage();
    }
  }

  Widget _buildDashboardPage() {
    final hasIncident = _incident != null;

    return ListView(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Emergency Command Center',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            if (hasIncident)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                ),
                onPressed: _clearIncidentDialog,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Issue All Clear'),
              )
            else
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                ),
                onPressed: _createIncidentDialog,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Start Emergency'),
              ),
          ],
        ),
        const SizedBox(height: 22),
        if (!hasIncident)
          _panel(
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 48,
                    color: Colors.green,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No active emergency',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text('Start an incident when an emergency is confirmed.'),
                ],
              ),
            ),
          )
        else ...[
          _incidentHeader(),
          const SizedBox(height: 18),


LayoutBuilder(
  builder: (context, constraints) {
    const cardHeight = 100.0;
    const spacing = 12.0;
    const minCardWidth = 308.0;

    final columns = ((constraints.maxWidth + spacing) /
            (minCardWidth + spacing))
        .floor()
        .clamp(1, 6);

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
childAspectRatio:
    (constraints.maxWidth - (columns - 1) * spacing) /
    columns /
    cardHeight,
      children: [
        _metricCard(
          'Expected people',
          _summary['expected'],
          Icons.groups_outlined,
          const Color(0xFF315D9D),
        ),
        _metricCard(
          'At assembly',
          _summary['at_assembly'],
          Icons.groups,
          Colors.green.shade700,
        ),
        _metricCard(
          'Safe outside',
          _summary['safe_elsewhere'],
          Icons.directions_walk,
          Colors.teal.shade700,
        ),
        _metricCard(
          'Still inside',
          _summary['safe_inside'],
          Icons.meeting_room_outlined,
          Colors.orange.shade800,
        ),
        _metricCard(
          'Help requested',
          _summary['help_requested'],
          Icons.health_and_safety_outlined,
          Colors.red.shade700,
        ),
        _metricCard(
          'No response',
          _summary['no_response'],
          Icons.person_search_outlined,
          Colors.deepOrange.shade700,
        ),
      ],
    );
  },
),

          const SizedBox(height: 20),

          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'People status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_summary['safe_confirmed'] ?? 0} of '
                  '${_summary['expected'] ?? 0} people have confirmed a '
                  'safe evacuation status.',
                ),
                const SizedBox(height: 18),
                _peopleFilterBar(),
                const SizedBox(height: 14),
                Builder(
                  builder: (context) {
                    final filteredPeople = _filterPeople(_people);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Showing ${filteredPeople.length} of '
                          '${_people.length} expected people',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _peopleTable(filteredPeople),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _incidentHeader() {
    final incident = _incident!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        border: Border.all(color: const Color(0xFFFFC5C5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, color: Colors.red.shade800, size: 34),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACTIVE INCIDENT #${incident['id']} · '
                  '${_string(incident['title'])}',
                  style: TextStyle(
                    color: Colors.red.shade900,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(_string(incident['message'])),
                const SizedBox(height: 6),
                Text('Location: ${_string(incident['location'])}'),
                Text('Triggered by: ${_string(incident['created_by'])}'),
                Text('Started: ${_date(incident['created_at'])}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String label, dynamic value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E9F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _string(value, '0'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeesPage() {
    final query = _searchController.text.toLowerCase();
    final list = _employees.where((employee) {
      final content = [
        employee['full_name'],
        employee['employee_code'],
        employee['email'],
      ].join(' ').toLowerCase();
      return content.contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Employees (${_employees.length})',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _employeeDialog(),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add Employee'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _searchField('Search name, employee ID or email'),
        const SizedBox(height: 14),
        Expanded(
          child: _panel(
            child: list.isEmpty
                ? const Center(child: Text('No employees found.'))
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Employee ID')),
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Email')),
                          DataColumn(label: Text('Account')),
                          DataColumn(label: Text('Password')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: list.map((employee) {
                          final active = _active(employee['is_active']);
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(_string(employee['employee_code'])),
                              ),
                              DataCell(Text(_string(employee['full_name']))),
                              DataCell(Text(_string(employee['email']))),
                              DataCell(
                                _statusChip(active ? 'ACTIVE' : 'INACTIVE'),
                              ),
                              DataCell(
                                Text(
                                  _active(employee['password_reset_required'])
                                      ? 'Reset required'
                                      : 'Set',
                                ),
                              ),
                              DataCell(
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: 'Edit employee',
                                      onPressed: () =>
                                          _employeeDialog(employee: employee),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          _setEmployeeActive(employee),
                                      child: Text(
                                        active ? 'Deactivate' : 'Activate',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildVisitorsPage() {
    final query = _searchController.text.toLowerCase();
    final list = _visitors.where((visitor) {
      final content = [
        visitor['full_name'],
        visitor['vrf_id'],
        visitor['email'],
      ].join(' ').toLowerCase();
      return content.contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Visitor Directory (${_visitors.length})',
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Visitors receive nine-hour access after successful email OTP '
          'verification. Expired visitors must sign in again to renew access.',
        ),
        const SizedBox(height: 14),
        _searchField('Search visitor name, VRF ID or email'),
        const SizedBox(height: 14),
        Expanded(
          child: _panel(
            child: list.isEmpty
                ? const Center(child: Text('No visitors found.'))
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('VRF ID')),
                          DataColumn(label: Text('Visitor')),
                          DataColumn(label: Text('Email')),
                          DataColumn(label: Text('Verified')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Last login')),
                          DataColumn(label: Text('Expires')),
                          DataColumn(label: Text('Action')),
                        ],
                        rows: list.map((visitor) {
                          final active = _active(visitor['is_active']);
                          return DataRow(
                            cells: [
                              DataCell(Text(_string(visitor['vrf_id']))),
                              DataCell(Text(_string(visitor['full_name']))),
                              DataCell(Text(_string(visitor['email']))),
                              DataCell(
                                Text(
                                  _active(visitor['email_verified'])
                                      ? 'Yes'
                                      : 'No',
                                ),
                              ),
                              DataCell(
                                _statusChip(active ? 'ACTIVE' : 'INACTIVE'),
                              ),
                              DataCell(Text(_date(visitor['last_login_at']))),
                              DataCell(Text(_date(visitor['expires_at']))),
                              DataCell(
                                TextButton(
                                  onPressed: () => _setVisitorActive(visitor),
                                  child: Text(
                                    active ? 'Deactivate' : 'Activate',
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildIncidentsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Incident History',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _createIncidentDialog,
              icon: const Icon(Icons.add_alert),
              label: const Text('Start incident'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => _pickDate(from: true),
              icon: const Icon(Icons.calendar_today),
              label: Text(
                _fromDate == null
                    ? 'From date'
                    : 'From: ${_dateOnly(_fromDate!)}',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickDate(from: false),
              icon: const Icon(Icons.calendar_today),
              label: Text(
                _toDate == null ? 'To date' : 'To: ${_dateOnly(_toDate!)}',
              ),
            ),
            FilledButton(
              onPressed: _applyIncidentFilters,
              child: const Text('Apply filters'),
            ),
            TextButton(
              onPressed: () async {
                setState(() {
                  _fromDate = null;
                  _toDate = null;
                });
                await _applyIncidentFilters();
              },
              child: const Text('Clear filters'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Records: ${_incidents.length}'),
        const SizedBox(height: 12),
        Expanded(
          child: _panel(
            child: _incidents.isEmpty
                ? const Center(
                    child: Text('No incidents found for this range.'),
                  )
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('ID')),
                          DataColumn(label: Text('Title')),
                          DataColumn(label: Text('Location')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Triggered by')),
                          DataColumn(label: Text('Created')),
                          DataColumn(label: Text('Cleared')),
                        ],
                        rows: _incidents.map((incident) {
                          final active =
                              _string(incident['status']) == 'ACTIVE';
                          return DataRow(
                            cells: [
                              DataCell(Text('#${incident['id']}')),
                              DataCell(Text(_string(incident['title']))),
                              DataCell(Text(_string(incident['location']))),
                              DataCell(
                                _statusChip(active ? 'ACTIVE' : 'CLEARED'),
                              ),
                              DataCell(Text(_string(incident['created_by']))),
                              DataCell(Text(_date(incident['created_at']))),
                              DataCell(Text(_date(incident['cleared_at']))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionPage() {
    final actionPeople = _people.where((person) {
      final status = _string(person['response_status']);
      return status == 'NO_RESPONSE' ||
          status == 'NEED_HELP' ||
          status == 'SAFE_INSIDE';
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Requires Action',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'No response, help requests and people still inside remain blockers '
          'until a safe evacuation status is confirmed.',
        ),
        const SizedBox(height: 16),
        if (_incident == null)
          const Expanded(
            child: Center(child: Text('There is no active incident.')),
          )
        else
          _panel(
            child: actionPeople.isEmpty
                ? const SizedBox(
                    height: 100,
                    child: Center(
                      child: Text('No people currently require action.'),
                    ),
                  )
                : _peopleTable(actionPeople, applyFilter: false),
          ),
      ],
    );
  }

  void _showHelpDetails(Map<String, dynamic> person) {
    final message = _string(
      person['message'],
      'No additional details provided.',
    );
    final location = _string(person['location_details']);
    final name = _string(person['name']);
    final identifier = _string(person['identifier']);
    final accountType = _string(person['account_type']);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.health_and_safety, color: Colors.red),
            SizedBox(width: 10),
            Expanded(child: Text('Emergency help request')),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Person',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text('$name ($identifier)'),
                const SizedBox(height: 16),
                const Text(
                  'Account type',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(accountType.toUpperCase()),
                const SizedBox(height: 16),
                const Text(
                  'Reported location',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(location),
                const SizedBox(height: 16),
                const Text(
                  'Help required / description',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    border: Border.all(color: const Color(0xFFFFC5C5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    message,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _personStatus(Map<String, dynamic> person) {
    return _string(person['response_status'], 'NO_RESPONSE').toUpperCase();
  }

  List<Map<String, dynamic>> _filterPeople(List<Map<String, dynamic>> people) {
    final query = _peopleSearchController.text.trim().toLowerCase();

    return people.where((person) {
      final status = _personStatus(person);

      final matchesFilter = switch (_peopleFilter) {
        'NO_RESPONSE' => status == 'NO_RESPONSE',
        'NEED_HELP' => status == 'NEED_HELP',
        'SAFE_INSIDE' => status == 'SAFE_INSIDE',
        'SAFE_OUTSIDE' => status == 'SAFE_OUTSIDE',
        'SAFE_AT_ASSEMBLY' => status == 'SAFE_AT_ASSEMBLY',
        'COMPLETED' => status != 'NO_RESPONSE',
        _ => true,
      };

      final searchableText = [
        person['name'],
        person['identifier'],
        person['account_type'],
        person['response_status'],
        person['location_details'],
      ].join(' ').toLowerCase();

      return matchesFilter && searchableText.contains(query);
    }).toList();
  }

  Widget _peopleFilterBar() {
    final options = <String, String>{
      'ALL': 'All expected people',
      'NO_RESPONSE': 'Not responded',
      'NEED_HELP': 'Need help',
      'SAFE_INSIDE': 'Safe inside',
      'SAFE_OUTSIDE': 'Safe outside',
      'SAFE_AT_ASSEMBLY': 'At assembly',
      'COMPLETED': 'Completed responses',
    };

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<String>(
            value: _peopleFilter,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Filter people',
              prefixIcon: Icon(Icons.filter_list),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            items: options.entries.map((entry) {
              return DropdownMenuItem<String>(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _peopleFilter = value);
            },
          ),
        ),
        SizedBox(
          width: 300,
          child: TextField(
            controller: _peopleSearchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Search people',
              hintText: 'Name or employee / visitor ID',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _peopleSearchController.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.close),
              ),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () {
            _peopleSearchController.clear();
            setState(() => _peopleFilter = 'ALL');
          },
          icon: const Icon(Icons.restart_alt),
          label: const Text('Reset'),
        ),
      ],
    );
  }

  Widget _peopleTable(
    List<Map<String, dynamic>> people, {
    bool applyFilter = true,
  }) {
    final visiblePeople = applyFilter ? _filterPeople(people) : people;

    if (visiblePeople.isEmpty) {
      return const SizedBox(
        height: 150,
        child: Center(child: Text('No people match the selected filter.')),
      );
    }

    final showHelpColumns = _peopleFilter == 'NEED_HELP';

    final showResponseDetails =
        _peopleFilter == 'ALL' || _peopleFilter == 'COMPLETED';

    final showEvacuationColumn =
        _peopleFilter == 'SAFE_OUTSIDE' || _peopleFilter == 'SAFE_AT_ASSEMBLY';

    final columns = <DataColumn>[
      const DataColumn(label: Text('Type')),
      const DataColumn(label: Text('Name / Identifier')),
      const DataColumn(label: Text('Response status')),
      const DataColumn(label: Text('Reported location')),
      if (showHelpColumns) ...[
        const DataColumn(label: Text('Help details')),
        const DataColumn(label: Text('Condition')),
        const DataColumn(label: Text('Evacuation')),
      ] else if (showResponseDetails)
        const DataColumn(label: Text('Response details')),
      if (showEvacuationColumn) const DataColumn(label: Text('Evacuation')),
      const DataColumn(label: Text('Response time')),
      const DataColumn(label: Text('Warden status')),
      const DataColumn(label: Text('Actions')),
    ];

    final rows = visiblePeople.map((person) {
      final type = _string(person['account_type'], 'employee');
      final status = _personStatus(person);
      final needsAction =
          status == 'NO_RESPONSE' ||
          status == 'NEED_HELP' ||
          status == 'SAFE_INSIDE';

      final message = _string(
        person['message'],
        'No additional details provided.',
      );

      final cells = <DataCell>[
        DataCell(_statusChip(type.toUpperCase())),
        DataCell(
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _string(person['name']),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  _string(person['identifier']),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
        DataCell(_statusChip(status)),
        DataCell(
          SizedBox(
            width: 160,
            child: Text(
              _string(person['location_details']),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ),
      ];

      if (showHelpColumns) {
        cells.addAll([
          DataCell(
            SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
                  TextButton(
                    onPressed: () => _showHelpDetails(person),
                    child: const Text('View full details'),
                  ),
                ],
              ),
            ),
          ),
          DataCell(
            SizedBox(
              width: 140,
              child: Text(_string(person['condition_status'])),
            ),
          ),
          DataCell(
            SizedBox(
              width: 150,
              child: Text(_string(person['evacuation_status'])),
            ),
          ),
        ]);
      } else if (showResponseDetails) {
        cells.add(
          DataCell(
            SizedBox(
              width: 220,
              child: status == 'NEED_HELP'
                  ? TextButton.icon(
                      onPressed: () => _showHelpDetails(person),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('View help details'),
                    )
                  : Text(
                      status == 'NO_RESPONSE'
                          ? 'No response submitted'
                          : _string(person['message'], 'No additional details'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        );
      }

      if (showEvacuationColumn) {
        cells.add(DataCell(Text(_string(person['evacuation_status']))));
      }

      cells.addAll([
        DataCell(Text(_date(person['responded_at']))),
        DataCell(
          SizedBox(
            width: 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _active(person['warden_dispatched'])
                      ? 'Dispatched'
                      : 'Not dispatched',
                ),
                if (_active(person['located']))
                  const Text(
                    'Located',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 180,
            child: Wrap(
              spacing: 4,
              children: [
                if (needsAction)
                  TextButton(
                    onPressed: () => _dispatchPerson(person),
                    child: const Text('Dispatch'),
                  ),
                if (status == 'NEED_HELP' && !_active(person['located']))
                  TextButton(
                    onPressed: () => _markLocated(person),
                    child: const Text('Mark located'),
                  ),
              ],
            ),
          ),
        ),
      ]);

      return DataRow(cells: cells);
    }).toList();

    final tableHeight = (56 + visiblePeople.length * 88)
        .clamp(144, 440)
        .toDouble();

    return SizedBox(
      height: tableHeight,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE1E6EF)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Scrollbar(
          controller: _peopleVerticalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _peopleVerticalController,
            scrollDirection: Axis.vertical,
            child: Scrollbar(
              controller: _peopleHorizontalController,
              thumbVisibility: true,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _peopleHorizontalController,
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xFFF0F4FA),
                  ),
                  headingTextStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF24364B),
                  ),
                  dataRowMinHeight: 64,
                  dataRowMaxHeight: 92,
                  columnSpacing: 24,
                  horizontalMargin: 18,
                  columns: columns,
                  rows: rows,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField(String hint) {
    return SizedBox(
      width: 460,
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color;

    switch (status.toUpperCase()) {
      case 'ACTIVE':
      case 'SAFE_AT_ASSEMBLY':
      case 'SAFE_OUTSIDE':
      case 'EMPLOYEE':
      case 'LOCATED':
        color = Colors.green.shade700;
        break;
      case 'CLEARED':
      case 'VISITOR':
        color = Colors.blue.shade700;
        break;
      case 'SAFE_INSIDE':
      case 'NO_RESPONSE':
      case 'INACTIVE':
        color = Colors.orange.shade800;
        break;
      case 'NEED_HELP':
        color = Colors.red.shade700;
        break;
      default:
        color = Colors.blueGrey.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E9F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
