import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../dates.dart';
import '../../theme/app_colors.dart';
import '../../widgets/labelled_field.dart';
import '../../widgets/upload_picker.dart';
import '../auth/auth_service.dart';
import '../auth/auth_widgets.dart';
import '../auth/otp_field.dart';
import 'agent_model.dart';
import 'agent_photo_picker.dart';
import 'agent_service.dart';

/// Which half of the flow is on screen.
enum _Step { details, otp }

/// Full agent registration: where the agent sits in the hierarchy, their KYC
/// details, and a one-time code sent to the number they gave — the same
/// two-step shape as the customer sign-in gate, but capturing a whole profile
/// rather than a name.
///
/// Pops `true` once an agent has been registered so the caller can refresh and
/// reveal the new row.
class AgentRegistrationScreen extends StatefulWidget {
  /// The subtree the parent may be chosen from — the signed-in agent.
  final Agent scopeRoot;

  /// The parent selected when the screen opens.
  final Agent initialParent;

  /// The tier to pre-select — the level of the open position the recruiter
  /// tapped. Null when the flow is opened without a specific slot in mind
  /// (the toolbar button), in which case it falls back to the first tier
  /// below [initialParent].
  final AgentLevel? initialLevel;

  /// The named slot the recruiter tapped — a zone ("South") for a region
  /// position, a state ("Kerala") for a state position. Fixes the new agent's
  /// area to it, and for a region position pre-selects and locks the zone
  /// dropdown. Null when the flow is opened from the toolbar.
  final String? initialArea;

  const AgentRegistrationScreen({
    super.key,
    required this.scopeRoot,
    required this.initialParent,
    this.initialLevel,
    this.initialArea,
  });

  @override
  State<AgentRegistrationScreen> createState() =>
      _AgentRegistrationScreenState();
}

class _AgentRegistrationScreenState extends State<AgentRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _dobText = TextEditingController();
  final _aadhaar = TextEditingController();
  final _pan = TextEditingController();
  final _address = TextEditingController();
  final _pincode = TextEditingController();
  final _place = TextEditingController();
  final _account = TextEditingController();
  final _otp = TextEditingController();

  DateTime? _dob;

  /// The profile photo, if the recruiter added one. Optional, and the only
  /// place it is ever set — the agent's detail screen shows it read-only.
  Uint8List? _photo;

  bool _submitted = false;

  late Agent _parent = widget.initialParent;
  late AgentLevel _level = _initialLevel();

  /// The cascade of fixed-slot picks that place the new agent: the zone, then
  /// (for a state agent or deeper) the state, then (for a district agent) the
  /// district. Each is picked from a list, never typed, and each is null until
  /// chosen or pinned by the parent / the tapped slot.
  String? _region;
  String? _state;
  String? _district;

  AgentLevel _initialLevel() {
    final levels = _levelsUnder(_parent);
    final wanted = widget.initialLevel;
    return wanted != null && levels.contains(wanted) ? wanted : levels.first;
  }

  _Step _step = _Step.details;
  bool _busy = false;
  String? _error;

  Timer? _cooldown;
  int _secondsLeft = 0;

  /// The parent options: the scope root and everything beneath it, minus the
  /// ward tier, which can hold no one.
  late final List<Agent> _parentChoices = [
    widget.scopeRoot,
    ...AgentService.instance.descendantsOf(widget.scopeRoot.id),
  ].where((agent) => agent.level != AgentLevel.ward).toList();

  List<AgentLevel> _levelsUnder(Agent parent) =>
      AgentService.instance.allowedChildLevels(parent);

  @override
  void initState() {
    super.initState();
    _otp.addListener(_clearErrorOnEdit);

    // A tapped "+ Kerala" / "+ South" / "+ Ernakulam" slot pins the whole
    // chain it belongs to — classify what kind of name it is and fill in
    // every tier at or above it.
    final tapped = widget.initialArea;
    if (tapped != null) {
      if (agentRegions.contains(tapped)) {
        _region = tapped;
      } else if (_zoneOfState(tapped) != null) {
        _region = _zoneOfState(tapped);
        _state = tapped;
      } else if (_stateOfDistrict(tapped) != null) {
        _state = _stateOfDistrict(tapped);
        _region = _zoneOfState(_state!);
        _district = tapped;
      }
    }

    // Anything the parent already fixes overrides a form pick.
    if (_parentRegion != null) _region = _parentRegion;
    if (_parentState != null) _state = _parentState;
  }

  /// The zone that owns [state] in [agentRegionStates], or null if none does.
  static String? _zoneOfState(String state) {
    for (final entry in agentRegionStates.entries) {
      if (entry.value.contains(state)) {
        return entry.key;
      }
    }
    return null;
  }

  /// The state that owns [district] in [agentStateDistricts], or null.
  static String? _stateOfDistrict(String district) {
    for (final entry in agentStateDistricts.entries) {
      if (entry.value.contains(district)) {
        return entry.key;
      }
    }
    return null;
  }

  // ---- The region → state → district cascade ----
  //
  // Each tier the new agent's level reaches gets a picker, unless the parent
  // it reports to (or the slot the recruiter tapped) already pins that tier.

  /// The zone the parent sits in, or null when the parent is above the zones.
  String? get _parentRegion {
    final p = _parent;
    if (p.level == AgentLevel.region && agentRegions.contains(p.area)) {
      return p.area;
    }
    final viaState = _parentState;
    return viaState == null ? null : _zoneOfState(viaState);
  }

  /// The state the parent sits in, or null when the parent is above the states.
  String? get _parentState {
    final p = _parent;
    if (p.level == AgentLevel.state && _zoneOfState(p.area) != null) {
      return p.area;
    }
    if (p.level == AgentLevel.district && _stateOfDistrict(p.area) != null) {
      return _stateOfDistrict(p.area);
    }
    return null;
  }

  /// True once the level reaches this tier — a district agent needs a zone, a
  /// state and a district; a state agent needs a zone and a state.
  bool get _levelReachesRegion =>
      _level.index >= AgentLevel.region.index &&
      _level.index <= AgentLevel.district.index;
  bool get _levelReachesState =>
      _level.index >= AgentLevel.state.index &&
      _level.index <= AgentLevel.district.index;
  bool get _levelReachesDistrict => _level == AgentLevel.district;

  /// The zone in force — the parent's, else the form pick.
  String? get _regionContext => _parentRegion ?? _region;

  /// The state in force — the parent's, else the form pick.
  String? get _stateContext => _parentState ?? _state;

  /// The states to choose from, or empty when the zone is unknown / unnamed.
  List<String> get _statesForRegion {
    final zone = _regionContext;
    return zone == null
        ? const <String>[]
        : agentRegionStates[zone] ?? const <String>[];
  }

  /// The districts to choose from, or empty when the state is unknown / has no
  /// named district slots (every state but Kerala, for now).
  List<String> get _districtsForState {
    final state = _stateContext;
    return state == null
        ? const <String>[]
        : agentStateDistricts[state] ?? const <String>[];
  }

  bool get _showRegionPicker => _levelReachesRegion && _parentRegion == null;
  bool get _showStatePicker =>
      _levelReachesState && _parentState == null && _statesForRegion.isNotEmpty;
  bool get _showDistrictPicker =>
      _levelReachesDistrict && _districtsForState.isNotEmpty;

  /// The zone / state / district picker is fixed (not a choice) when the
  /// recruiter came in through a named slot that pins that tier.
  bool get _regionLocked {
    final ia = widget.initialArea;
    return ia != null &&
        (agentRegions.contains(ia) ||
            _zoneOfState(ia) != null ||
            _stateOfDistrict(ia) != null);
  }

  bool get _stateLocked {
    final ia = widget.initialArea;
    return ia != null &&
        (_zoneOfState(ia) != null || _stateOfDistrict(ia) != null);
  }

  bool get _districtLocked {
    final ia = widget.initialArea;
    return ia != null && _stateOfDistrict(ia) != null;
  }

  /// The named slot this agent fills — the deepest pick its level reaches,
  /// falling back to a tapped slot name.
  String? get _slotArea {
    if (_level == AgentLevel.region) return _region ?? widget.initialArea;
    if (_level == AgentLevel.state) return _state ?? widget.initialArea;
    if (_level == AgentLevel.district) return _district ?? widget.initialArea;
    return widget.initialArea;
  }

  /// Drops any cascade pick that its parent tier no longer allows — called
  /// after the parent, the level, or a higher pick changes.
  void _syncCascade() {
    if (!_statesForRegion.contains(_state)) _state = null;
    if (!_districtsForState.contains(_district)) _district = null;
  }

  @override
  void dispose() {
    _cooldown?.cancel();
    for (final c in [
      _first,
      _middle,
      _last,
      _phone,
      _dobText,
      _aadhaar,
      _pan,
      _address,
      _pincode,
      _place,
      _account,
    ]) {
      c.dispose();
    }
    _otp
      ..removeListener(_clearErrorOnEdit)
      ..dispose();
    super.dispose();
  }

  void _clearErrorOnEdit() {
    if (_error != null && mounted) {
      setState(() => _error = null);
    }
  }

  void _onParentChanged(String? id) {
    final parent = _parentChoices.firstWhere((agent) => agent.id == id);
    setState(() {
      _parent = parent;
      final levels = _levelsUnder(parent);
      if (!levels.contains(_level)) {
        _level = levels.first;
      }
      // Whatever the new parent already pins wins over an old form pick;
      // tiers the level no longer reaches are dropped.
      if (_parentRegion != null) _region = _parentRegion;
      if (_parentState != null) _state = _parentState;
      if (!_levelReachesRegion) _region = null;
      if (!_levelReachesState) _state = null;
      if (!_levelReachesDistrict) _district = null;
      _syncCascade();
    });
  }

  Future<void> _pickDob() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(now.year - 90),
      // An agent has to be an adult.
      lastDate: DateTime(now.year - 18, now.month, now.day),
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobText.text = formatDate(picked);
      });
    }
  }

  Future<void> _pickPhoto() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => const _PhotoSourceSheet(),
    );
    if (source == null || !mounted) {
      return;
    }
    final bytes = await const AgentPhotoPicker().pick(source);
    if (bytes != null && mounted) {
      setState(() => _photo = bytes);
    }
  }

  // ---- Actions ----

  Future<void> _sendOtp() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final formOk = _formKey.currentState?.validate() ?? false;
    setState(() => _submitted = true);
    final regionMissing =
        _showRegionPicker && !agentRegions.contains(_region);
    final stateMissing =
        _showStatePicker && !_statesForRegion.contains(_state);
    final districtMissing =
        _showDistrictPicker && !_districtsForState.contains(_district);
    if (!formOk ||
        _dob == null ||
        regionMissing ||
        stateMissing ||
        districtMissing) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) {
      return;
    }

    _otp.clear();
    setState(() {
      _busy = false;
      _step = _Step.otp;
    });
    _startCooldown();
    _announceCode();
  }

  void _resend() {
    if (_secondsLeft > 0) {
      return;
    }
    _otp.clear();
    setState(() => _error = null);
    _startCooldown();
    _announceCode();
  }

  Future<void> _verify([String? completed]) async {
    final code = completed ?? _otp.text;
    if (code.length < AuthService.otpLength) {
      setState(() => _error = 'Enter the ${AuthService.otpLength}-digit code');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) {
      return;
    }

    if (code.trim() != AuthService.demoOtp) {
      setState(() {
        _busy = false;
        _error = 'That code is incorrect. Check the SMS and try again.';
      });
      return;
    }

    final failure = AgentService.instance.registerAgent(
      parent: _parent,
      level: _level,
      firstName: _first.text,
      middleName: _middle.text,
      lastName: _last.text,
      phone: _phone.text,
      dob: _dob!,
      aadhaar: _aadhaar.text,
      pan: _pan.text,
      address: _address.text,
      pincode: _pincode.text,
      place: _place.text,
      accountNumber: _account.text,
      area: _slotArea,
      photoBytes: _photo,
    );
    if (failure != null) {
      // Something the field checks let through — send them back to fix it.
      setState(() {
        _busy = false;
        _step = _Step.details;
        _error = failure;
      });
      return;
    }

    _cooldown?.cancel();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    Navigator.of(context).pop(true);
  }

  void _backToDetails() {
    _cooldown?.cancel();
    _otp.clear();
    setState(() {
      _step = _Step.details;
      _error = null;
      _secondsLeft = 0;
    });
  }

  void _startCooldown() {
    _cooldown?.cancel();
    setState(() => _secondsLeft = AuthService.resendCooldown.inSeconds);
    _cooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
      }
    });
  }

  void _announceCode() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(
            'OTP sent to +91 ${_phone.text} · demo code ${AuthService.demoOtp}',
          ),
        ),
      );
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == _Step.details,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _backToDetails();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          backgroundColor: AppColors.white,
          surfaceTintColor: AppColors.white,
          elevation: 0,
          title: Text(
            _step == _Step.details ? 'Agent registration' : 'Verify number',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: AppColors.border),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: _step == _Step.details ? _buildDetails() : _buildOtp(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetails() {
    final levels = _levelsUnder(_parent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthHeading(
          title: 'Register an agent',
          subtitle:
              'Place them in your team, capture their details, then verify '
              'their mobile number with a one-time code.',
        ),
        const SizedBox(height: 20),

        Center(
          child: _PhotoPickerField(
            photo: _photo,
            onPick: _pickPhoto,
            onRemove: () => setState(() => _photo = null),
          ),
        ),
        const SizedBox(height: 22),

        _Label('Reports to'),
        DropdownButtonFormField<String>(
          initialValue: _parent.id,
          isExpanded: true,
          decoration: shieldFieldDecoration(),
          items: [
            for (final agent in _parentChoices)
              DropdownMenuItem(
                value: agent.id,
                child: Text(
                  '${agent.name} · ${agent.level.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _onParentChanged,
        ),
        const SizedBox(height: 14),

        _Label('Level'),
        DropdownButtonFormField<AgentLevel>(
          initialValue: _level,
          isExpanded: true,
          decoration: shieldFieldDecoration(),
          items: [
            for (final level in levels)
              DropdownMenuItem(value: level, child: Text(level.label)),
          ],
          onChanged: (level) {
            if (level != null) {
              setState(() {
                _level = level;
                if (!_levelReachesRegion) _region = null;
                if (!_levelReachesState) _state = null;
                if (!_levelReachesDistrict) _district = null;
                _syncCascade();
              });
            }
          },
        ),
        if (_showRegionPicker) ...[
          const SizedBox(height: 14),
          _Label('Region'),
          DropdownButtonFormField<String>(
            initialValue: _region,
            isExpanded: true,
            decoration: shieldFieldDecoration(hint: 'Pick a region'),
            items: [
              for (final region in agentRegions)
                DropdownMenuItem(value: region, child: Text(region)),
            ],
            // Fixed when the recruiter tapped a named slot that pins the zone.
            onChanged: _regionLocked
                ? null
                : (region) => setState(() {
                    _region = region;
                    _syncCascade();
                  }),
          ),
          if (_submitted && _region == null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                _level == AgentLevel.region
                    ? 'Choose which region this agent heads'
                    : 'Choose which region this agent sits under',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.danger,
                ),
              ),
            ),
        ],
        if (_showStatePicker) ...[
          const SizedBox(height: 14),
          _Label('State'),
          DropdownButtonFormField<String>(
            initialValue: _statesForRegion.contains(_state) ? _state : null,
            isExpanded: true,
            decoration: shieldFieldDecoration(hint: 'Pick a state'),
            items: [
              for (final state in _statesForRegion)
                DropdownMenuItem(value: state, child: Text(state)),
            ],
            // Fixed when the recruiter tapped a named slot that pins the state.
            onChanged: _stateLocked
                ? null
                : (state) => setState(() {
                    _state = state;
                    _syncCascade();
                  }),
          ),
          if (_submitted && _state == null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                _level == AgentLevel.state
                    ? 'Choose which state this agent heads'
                    : 'Choose which state this agent sits under',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.danger,
                ),
              ),
            ),
        ],
        if (_showDistrictPicker) ...[
          const SizedBox(height: 14),
          _Label('District'),
          DropdownButtonFormField<String>(
            initialValue:
                _districtsForState.contains(_district) ? _district : null,
            isExpanded: true,
            decoration: shieldFieldDecoration(hint: 'Pick a district'),
            items: [
              for (final district in _districtsForState)
                DropdownMenuItem(value: district, child: Text(district)),
            ],
            // Fixed when the recruiter tapped a named "+ Ernakulam" slot.
            onChanged: _districtLocked
                ? null
                : (district) => setState(() => _district = district),
          ),
          if (_submitted && _district == null)
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'Choose which district this agent heads',
                style: TextStyle(fontSize: 12.5, color: AppColors.danger),
              ),
            ),
        ],
        const SizedBox(height: 18),

        Form(
          key: _formKey,
          autovalidateMode: _submitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabelledField(
                label: 'First name',
                hint: 'First name',
                controller: _first,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [LengthLimitingTextInputFormatter(30)],
                validator: (v) =>
                    AgentService.validateName(v, field: 'first name'),
              ),
              const SizedBox(height: 14),
              LabelledField(
                label: 'Middle name (optional)',
                hint: 'Middle name',
                controller: _middle,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [LengthLimitingTextInputFormatter(30)],
                validator: AgentService.validateMiddleName,
              ),
              const SizedBox(height: 14),
              LabelledField(
                label: 'Last name',
                hint: 'Last name',
                controller: _last,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [LengthLimitingTextInputFormatter(30)],
                validator: (v) =>
                    AgentService.validateName(v, field: 'last name'),
              ),
              const SizedBox(height: 14),
              LabelledField(
                label: 'Mobile number',
                hint: '10-digit mobile number',
                controller: _phone,
                prefixText: '+91  ',
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: AgentService.validatePhone,
              ),
              const SizedBox(height: 14),
              LabelledField(
                label: 'Date of birth',
                hint: 'Select date',
                controller: _dobText,
                readOnly: true,
                onTap: _pickDob,
                icon: Icons.event_rounded,
                validator: (_) => _dob == null ? 'Date of birth is required'
                    : null,
              ),
              const SizedBox(height: 14),
              LabelledField(
                label: 'Aadhaar number',
                hint: '12-digit Aadhaar',
                controller: _aadhaar,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(12),
                ],
                validator: AgentService.validateAadhaar,
              ),
              const SizedBox(height: 14),
              LabelledField(
                label: 'PAN',
                hint: 'ABCDE1234F',
                controller: _pan,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(10),
                  TextInputFormatter.withFunction(
                    (_, next) => next.copyWith(text: next.text.toUpperCase()),
                  ),
                ],
                validator: AgentService.validatePan,
              ),
              const SizedBox(height: 14),
              LabelledField(
                label: 'Address',
                hint: 'House / street / locality',
                controller: _address,
                textCapitalization: TextCapitalization.words,
                maxLines: 2,
                validator: (v) =>
                    AgentService.validateRequired(v, 'address'),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LabelledField(
                      label: 'PIN code',
                      hint: '6 digits',
                      controller: _pincode,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      validator: AgentService.validatePincode,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabelledField(
                      label: 'Place',
                      hint: 'Town / village',
                      controller: _place,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          AgentService.validateRequired(v, 'place'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LabelledField(
                label: 'Bank account number',
                hint: 'Account the commission is paid into',
                controller: _account,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(18),
                ],
                validator: AgentService.validateAccountNumber,
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          AuthErrorNote(message: _error!),
        ],
        const SizedBox(height: 18),
        AuthButton(label: 'Send OTP', busy: _busy, onPressed: _sendOtp),
      ],
    );
  }

  Widget _buildOtp() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthHeading(
          title: 'Verify the mobile number',
          subtitle:
              'Enter the ${AuthService.otpLength}-digit code sent to '
              '+91 ${_phone.text}.',
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : _backToDetails,
            icon: const Icon(Icons.arrow_back_rounded, size: 17),
            label: const Text('Change details'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandBlue,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        OtpField(
          controller: _otp,
          length: AuthService.otpLength,
          hasError: _error != null,
          onCompleted: _verify,
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          AuthErrorNote(message: _error!),
        ],
        const SizedBox(height: 14),
        _ResendRow(secondsLeft: _secondsLeft, onResend: _resend),
        const SizedBox(height: 18),
        AuthButton(
          label: 'Verify & submit',
          busy: _busy,
          onPressed: _verify,
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppColors.offerTint,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(
            'Demo mode · the code is ${AuthService.demoOtp}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.brandBlue,
            ),
          ),
        ),
      ],
    );
  }
}

/// The optional profile photo, captured here at registration and nowhere
/// else — the agent's own detail screen only ever shows it. Tapping the
/// circle or the button under it opens the camera-or-gallery sheet; a chosen
/// photo can be cleared again while this screen is still open.
class _PhotoPickerField extends StatelessWidget {
  final Uint8List? photo;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _PhotoPickerField({
    required this.photo,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = photo;
    final has = bytes != null;

    return Column(
      children: [
        GestureDetector(
          onTap: onPick,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.pageTint,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border, width: 1.4),
                ),
                alignment: Alignment.center,
                child: has
                    ? ClipOval(
                        child: Image.memory(
                          bytes,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(
                        Icons.person_rounded,
                        size: 40,
                        color: AppColors.textMuted,
                      ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 2),
                  ),
                  child: Icon(
                    has ? Icons.edit_rounded : Icons.camera_alt_rounded,
                    size: 14,
                    color: AppColors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: onPick,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppColors.brandBlue,
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Text(has ? 'Change photo' : 'Add profile photo'),
            ),
            if (has)
              TextButton(
                onPressed: onRemove,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.danger,
                  textStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const Text('Remove'),
              ),
          ],
        ),
        if (!has)
          const Text(
            'Optional',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
      ],
    );
  }
}

/// Camera or gallery — the choice behind adding a registration profile photo.
class _PhotoSourceSheet extends StatelessWidget {
  const _PhotoSourceSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Add profile photo',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              UploadSourceTile(
                icon: Icons.photo_camera_outlined,
                label: 'Camera',
                enabled: true,
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              const SizedBox(width: 10),
              UploadSourceTile(
                icon: Icons.photo_library_outlined,
                label: 'Gallery',
                enabled: true,
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textBody,
        ),
      ),
    );
  }
}

/// Countdown, then a live resend link — the same control the sign-in gate uses.
class _ResendRow extends StatelessWidget {
  final int secondsLeft;
  final VoidCallback onResend;

  const _ResendRow({required this.secondsLeft, required this.onResend});

  @override
  Widget build(BuildContext context) {
    if (secondsLeft > 0) {
      final seconds = secondsLeft.toString().padLeft(2, '0');
      return Text(
        'Resend code in 0:$seconds',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Did not get the code?',
          style: TextStyle(fontSize: 13.5, color: AppColors.textBody),
        ),
        TextButton(
          onPressed: onResend,
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Resend OTP',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.brandBlue,
            ),
          ),
        ),
      ],
    );
  }
}
