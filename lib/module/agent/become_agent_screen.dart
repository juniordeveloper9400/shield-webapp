import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/backend/agent_repository.dart';
import '../../dates.dart';
import '../../theme/app_colors.dart';
import '../../widgets/labelled_field.dart';
import '../auth/auth_widgets.dart';
import '../registration/registration_flow.dart';
import '../registration/registration_required_screen.dart';
import '../registration/registration_service.dart';
import 'agent_model.dart';
import 'agent_service.dart';

/// A plain member's own request to become a Sahakar 360 agent — distinct from
/// [AgentRegistrationScreen], which is a signed-in *agent* recruiting someone
/// else under them and needs a parent to place that person against. There is
/// no recruiter here: the request is filed under the signed-in member's own
/// identity (`agent.service.ts`'s `submitRequest` resolves it from the
/// session, not from anything this form sends), and the admin console
/// assigns the real level, parent and position at approval time — same as it
/// already does for every other request.
///
/// The one thing this form asks for beyond the standard KYC fields is a
/// ward: an application has to start *somewhere* on the map, and starting at
/// the bottom of the hierarchy — not claiming a region or a state outright —
/// is the honest default for a first-time applicant. Admin can move it up
/// when they review it.
class BecomeAgentScreen extends StatefulWidget {
  const BecomeAgentScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BecomeAgentScreen()),
    );
  }

  @override
  State<BecomeAgentScreen> createState() => _BecomeAgentScreenState();
}

class _BecomeAgentScreenState extends State<BecomeAgentScreen> {
  final _formKey = GlobalKey<FormState>();

  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  final _dobText = TextEditingController();
  final _aadhaar = TextEditingController();
  final _pan = TextEditingController();
  final _address = TextEditingController();
  final _pincode = TextEditingController();
  final _place = TextEditingController();
  final _account = TextEditingController();

  DateTime? _dob;
  bool _submitted = false;
  bool _busy = false;
  String? _error;

  static const List<AgentLevel> _cascade = [...agentNamedTiers, AgentLevel.ward];
  final Map<AgentLevel, GeoSlot> _picks = {};

  /// Null while the check is still in flight, then whichever of the
  /// member's own requests is still PENDING, if any — this screen shows
  /// that instead of the form rather than let a second application pile up
  /// behind the first.
  OwnAgentRequest? _pendingRequest;
  bool _loadingStatus = true;

  @override
  void initState() {
    super.initState();
    AgentGeo.instance.ensureLoaded();
    _prefillFromRegistration();
    _loadOwnStatus();
  }

  @override
  void dispose() {
    _first.dispose();
    _middle.dispose();
    _last.dispose();
    _dobText.dispose();
    _aadhaar.dispose();
    _pan.dispose();
    _address.dispose();
    _pincode.dispose();
    _place.dispose();
    _account.dispose();
    super.dispose();
  }

  /// Best-effort head start from the member's own completed registration —
  /// name, DOB and address are already on file there, so there's no reason
  /// to make someone type them twice. Never blocks: a field it can't fill
  /// just stays blank, same as an application starting from scratch.
  void _prefillFromRegistration() {
    final profile = RegistrationService.instance.profile;
    if (profile == null) {
      return;
    }
    final parts = profile.name.trim().split(RegExp(r'\s+'));
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      _first.text = parts.first;
    }
    if (parts.length > 1) {
      _last.text = parts.sublist(1).join(' ');
    }
    _dob = profile.dob;
    _dobText.text = formatDate(profile.dob);
    _address.text = profile.address;
    _pincode.text = profile.pincode;
    _place.text = profile.place;
  }

  Future<void> _loadOwnStatus() async {
    final requests = await AgentRepository.instance.fetchOwnRequests();
    if (!mounted) {
      return;
    }
    OwnAgentRequest? pending;
    for (final r in requests ?? const <OwnAgentRequest>[]) {
      if (r.isPending) {
        pending = r;
        break;
      }
    }
    setState(() {
      _pendingRequest = pending;
      _loadingStatus = false;
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

  List<GeoSlot> _optionsFor(AgentLevel level) {
    final index = _cascade.indexOf(level);
    if (index == 0) {
      return AgentGeo.current.slotsUnder(level, null);
    }
    final parent = _picks[_cascade[index - 1]];
    if (parent == null) {
      return const [];
    }
    return AgentGeo.current.slotsUnder(level, parent.id);
  }

  void _onPick(AgentLevel level, GeoSlot? value) {
    setState(() {
      if (value == null) {
        _picks.remove(level);
      } else {
        _picks[level] = value;
      }
      // Picking (or changing) a wider tier invalidates whatever was chosen
      // under it — a new region means the state/district/... picked against
      // the old one no longer means anything.
      final index = _cascade.indexOf(level);
      for (var i = index + 1; i < _cascade.length; i++) {
        _picks.remove(_cascade[i]);
      }
    });
  }

  Future<void> _submit() async {
    final formOk = _formKey.currentState?.validate() ?? false;
    setState(() => _submitted = true);
    final ward = _picks[AgentLevel.ward];
    if (!formOk || _dob == null || ward == null) {
      setState(() {
        _error = ward == null && formOk
            ? 'Choose your ward before submitting.'
            : null;
      });
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    final outcome = await AgentRepository.instance.submitOwnAgentRequest(
      level: AgentLevel.ward,
      area: ward.name,
      areaId: ward.id,
      firstName: _first.text,
      middleName: _middle.text,
      lastName: _last.text,
      dob: _dob!,
      aadhaar: _aadhaar.text,
      pan: _pan.text,
      address: _address.text,
      pincode: _pincode.text,
      place: _place.text,
      accountNumber: _account.text,
    );
    if (!mounted) {
      return;
    }
    if (!outcome.ok) {
      setState(() {
        _busy = false;
        _error = outcome.error ?? 'Could not submit your application. Please try again.';
      });
      return;
    }

    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sent for approval'),
        content: const Text(
          "Your application has been submitted. An admin will review your "
          'details and get back to you once a decision is made.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RegistrationService.instance,
      builder: (context, _) => RegistrationService.instance.isRegistered
          ? _buildBody(context)
          : RegistrationRequiredScreen(
              title: 'Become a Sahakar 360 Agent',
              onComplete: () => RegistrationFlow.show(context),
            ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Become a Sahakar 360 Agent',
          style: TextStyle(
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
        child: _loadingStatus
            ? const Center(child: CircularProgressIndicator())
            : _pendingRequest != null
                ? _PendingStatusView(request: _pendingRequest!)
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: _buildForm(),
                    ),
                  ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthHeading(
          title: 'Apply to become an agent',
          subtitle:
              'Tell us about yourself and where you work from — an admin '
              'reviews every application and sets your final position.',
        ),
        const SizedBox(height: 20),
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
                validator: (v) => AgentService.validateName(v, field: 'first name'),
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
                validator: (v) => AgentService.validateName(v, field: 'last name'),
              ),
              const SizedBox(height: 14),
              LabelledField(
                label: 'Date of birth',
                hint: 'DD/MM/YYYY',
                controller: _dobText,
                readOnly: true,
                onTap: _pickDob,
                validator: (_) => _dob == null ? 'Date of birth is required' : null,
              ),
              const SizedBox(height: 14),
              LabelledField(
                label: 'Aadhaar number',
                hint: '12-digit Aadhaar number',
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
                label: 'PAN number',
                hint: '10-character PAN',
                controller: _pan,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(10),
                  UpperCaseTextFormatter(),
                ],
                validator: AgentService.validatePan,
              ),
              const SizedBox(height: 14),
              LabelledField(
                label: 'Address',
                hint: 'House, street, locality',
                controller: _address,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => AgentService.validateRequired(v, 'address'),
              ),
              const SizedBox(height: 14),
              LabelledField(
                label: 'Pincode',
                hint: '6-digit pincode',
                controller: _pincode,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                validator: AgentService.validatePincode,
              ),
              const SizedBox(height: 14),
              LabelledField(
                label: 'Place',
                hint: 'Town / village',
                controller: _place,
                textCapitalization: TextCapitalization.words,
                validator: (v) => AgentService.validateRequired(v, 'place'),
              ),
              const SizedBox(height: 14),
              LabelledField(
                label: 'Bank account number',
                hint: 'For commission payouts',
                controller: _account,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: AgentService.validateAccountNumber,
              ),
              const SizedBox(height: 20),
              const _SectionLabel('Where you\'ll work from'),
              const SizedBox(height: 4),
              const Text(
                'Pick your ward — admin may adjust this when they review '
                'your application.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              for (final level in _cascade) ...[
                _GeoDropdown(
                  level: level,
                  value: _picks[level],
                  options: _optionsFor(level),
                  onChanged: (v) => _onPick(level, v),
                ),
                const SizedBox(height: 12),
              ],
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 13, color: AppColors.danger),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 6),
              AuthButton(
                label: 'Submit application',
                busy: _busy,
                onPressed: _busy ? null : _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: AppColors.textDark,
      ),
    );
  }
}

class _GeoDropdown extends StatelessWidget {
  final AgentLevel level;
  final GeoSlot? value;
  final List<GeoSlot> options;
  final ValueChanged<GeoSlot?> onChanged;

  const _GeoDropdown({
    required this.level,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = options.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            level.label,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textBody,
            ),
          ),
        ),
        DropdownButtonFormField<GeoSlot>(
          initialValue: value != null && options.contains(value) ? value : null,
          isExpanded: true,
          decoration: shieldFieldDecoration(
            hint: enabled ? 'Select ${level.label.toLowerCase()}' : 'Choose the tier above first',
          ),
          items: [
            for (final option in options)
              DropdownMenuItem(value: option, child: Text(option.name)),
          ],
          onChanged: enabled ? onChanged : null,
          validator: (_) => level == AgentLevel.ward && value == null
              ? 'Choose your ward'
              : null,
        ),
      ],
    );
  }
}

/// What this screen shows in place of the form once the member already has
/// a request awaiting review — a second submission on top of it would just
/// confuse the queue admin already sees.
class _PendingStatusView extends StatelessWidget {
  final OwnAgentRequest request;

  const _PendingStatusView({required this.request});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.hourglass_top_rounded,
            size: 56,
            color: AppColors.brandBlue,
          ),
          const SizedBox(height: 18),
          const Text(
            'Application under review',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You applied for a ${request.level.label} position'
            '${request.area.isNotEmpty ? ' at ${request.area}' : ''} on '
            '${formatDate(request.createdAt)}. An admin will review it and '
            'you\'ll get agent access once approved.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: AppColors.textBody,
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps the PAN field always uppercase as it's typed, the same way the
/// field is validated (`AgentService.validatePan` expects upper case).
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
