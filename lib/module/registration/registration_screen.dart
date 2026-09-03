import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../widgets/age_badge.dart';
import '../../widgets/labelled_field.dart';
import '../auth/auth_service.dart';
import 'registration_celebration.dart';
import 'registration_service.dart';
import 'store_map_picker.dart';

/// The registration form: profile, address, and the branch that will serve it.
///
/// Offered, never imposed. It carries a close in the header and a skip beside
/// the submit, and both leave the member exactly where they were — the reward
/// is the reason to fill it in, not a locked door.
class RegistrationScreen extends StatefulWidget {
  /// Prefills from the saved profile and drops the reward copy, so the same
  /// form serves editing without pretending there is a second reward.
  final bool isEditing;

  const RegistrationScreen({super.key, this.isEditing = false});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _place = TextEditingController();
  final _pincode = TextEditingController();

  /// Filled by the picker only, never typed into — see the field below.
  final _dobText = TextEditingController();

  Gender? _gender;
  DateTime? _dob;
  String? _state;
  String? _storeId;

  /// Once the member picks a branch themselves, the map must not quietly move
  /// their choice when a fresh location fix lands.
  bool _storePickedByHand = false;

  /// The branch map needs a location fix before a branch can be chosen — the
  /// form cannot be submitted until this is true.
  bool _locationReady = false;

  bool _submitted = false;

  RegistrationService get _service => RegistrationService.instance;

  @override
  void initState() {
    super.initState();

    final profile = _service.profile;
    final session = AuthService.instance.currentUser;

    // The name and number come from the session when there is no profile yet:
    // both were established at sign-in, and asking twice reads as a mistake.
    _name.text = profile?.name ?? session.value?.name ?? '';
    _phone.text = profile?.phone ?? session.value?.phone ?? '';
    _email.text = profile?.email ?? '';
    _address.text = profile?.address ?? '';
    _place.text = profile?.place ?? '';
    _pincode.text = profile?.pincode ?? '';
    _gender = profile?.gender;
    _dob = profile?.dob;
    _dobText.text = profile == null ? '' : Registration.formatDate(profile.dob);
    _state = profile?.state;
    _storeId = profile?.storeId;
    _storePickedByHand = profile != null;

  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _place.dispose();
    _pincode.dispose();
    _dobText.dispose();
    super.dispose();
  }

  // ---- Pickers ----

  Future<void> _pickDob() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 110),
      lastDate: now,
      helpText: 'Date of birth',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.brandBlue,
            onPrimary: AppColors.white,
            onSurface: AppColors.textDark,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _dob = picked;
        _dobText.text = Registration.formatDate(picked);
      });
    }
  }

  Future<void> _pickState() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _StatePicker(selected: _state),
    );
    if (picked != null && mounted) {
      setState(() => _state = picked);
    }
  }

  // ---- Actions ----

  void _close() {
    // Closing is an answer, not an accident: the prompt stands down for the
    // session rather than reappearing on the next screen.
    if (!_service.isRegistered) {
      _service.dismissPrompt();
    }
    _leave(false);
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _submitted = true);

    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk ||
        _gender == null ||
        _dob == null ||
        !_locationReady ||
        _storeId == null) {
      return;
    }

    _service.save(
      Registration(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        gender: _gender!,
        dob: _dob!,
        address: _address.text.trim(),
        place: _place.text.trim(),
        pincode: _pincode.text.trim(),
        state: _state!,
        storeId: _storeId!,
      ),
    );

    // Show the confirmation on this route while it is still up, then close the
    // form once the member dismisses it.
    await showRegistrationCelebration(context, isEditing: widget.isEditing);
    if (!mounted) {
      return;
    }
    _leave(true);
  }

  /// Closes the form. Guarded because the screen is always pushed in the app
  /// but can be mounted as a whole route on its own.
  void _leave(bool registered) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(registered);
    }
  }

  // ---- Validators ----

  String? _validateEmail(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return 'Email is required';
    }
    if (!RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(text)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _required(String? value, String message) =>
      (value ?? '').trim().isEmpty ? message : null;

  String? _validatePincode(String? value) {
    final text = (value ?? '').trim();
    if (text.length != 6 || int.tryParse(text) == null) {
      return 'Enter a valid 6-digit pincode';
    }
    return null;
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          widget.isEditing ? 'Registration details' : 'Complete registration',
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _close,
            icon: const Icon(Icons.close_rounded, size: 22),
            color: AppColors.textMuted,
            tooltip: 'Close',
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (!widget.isEditing) const _RewardNote(),
            if (!widget.isEditing) const SizedBox(height: 14),
            _buildAboutYou(),
            const SizedBox(height: 14),
            _buildAddress(),
            const SizedBox(height: 14),
            _buildStorePicker(),
          ],
        ),
      ),
      bottomNavigationBar: _buildActions(),
    );
  }

  Widget _buildAboutYou() {
    return _Section(
      title: 'About you',
      subtitle: 'Your number is already verified and cannot be changed here.',
      children: [
        LabelledField(
          label: 'Full name',
          hint: 'Enter your name',
          controller: _name,
          icon: Icons.person_outline_rounded,
          textCapitalization: TextCapitalization.words,
          validator: AuthService.validateName,
        ),
        const SizedBox(height: 14),
        LabelledField(
          label: 'Mobile number',
          hint: '10-digit mobile number',
          controller: _phone,
          icon: Icons.phone_iphone_rounded,
          prefixText: '+91  ',
          readOnly: true,
          suffix: const Icon(
            Icons.verified_rounded,
            size: 19,
            color: AppColors.brandGreenDeep,
          ),
        ),
        const SizedBox(height: 14),
        LabelledField(
          label: 'Email address',
          hint: 'you@example.com',
          controller: _email,
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          validator: _validateEmail,
        ),
        const SizedBox(height: 14),
        _FieldLabel('Gender'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in Gender.values)
              _ChoicePill(
                label: option.label,
                selected: _gender == option,
                onTap: () => setState(() => _gender = option),
              ),
          ],
        ),
        if (_submitted && _gender == null) const _FieldError('Pick one'),
        const SizedBox(height: 14),
        LabelledField(
          label: 'Date of birth',
          hint: 'Select your date of birth',
          // A read-only field opening the picker: typing a date invites every
          // format under the sun, and the picker is the only source here.
          controller: _dobText,
          icon: Icons.cake_outlined,
          readOnly: true,
          onTap: _pickDob,
          // The age rides in the field itself: it is derived from the date the
          // moment one is picked, never asked for as a second answer.
          suffix: DobFieldSuffix(dob: _dob),
        ),
        if (_submitted && _dob == null)
          const _FieldError('Date of birth is required'),
      ],
    );
  }

  Widget _buildAddress() {
    return _Section(
      title: 'Where you are',
      subtitle: 'Used for delivery, and to find the branch nearest you.',
      children: [
        LabelledField(
          label: 'Address',
          hint: 'House / flat, street',
          controller: _address,
          maxLines: 3,
          textCapitalization: TextCapitalization.words,
          validator: (value) => _required(value, 'Address is required'),
        ),
        const SizedBox(height: 14),
        LabelledField(
          label: 'Place',
          hint: 'Town or locality',
          controller: _place,
          icon: Icons.location_city_rounded,
          textCapitalization: TextCapitalization.words,
          validator: (value) => _required(value, 'Place is required'),
        ),
        const SizedBox(height: 14),
        LabelledField(
          label: 'Pincode',
          hint: '6-digit pincode',
          controller: _pincode,
          icon: Icons.markunread_mailbox_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          validator: _validatePincode,
        ),
        const SizedBox(height: 14),
        _FieldLabel('State'),
        const SizedBox(height: 6),
        InkWell(
          onTap: _pickState,
          borderRadius: BorderRadius.circular(10),
          child: InputDecorator(
            decoration: shieldFieldDecoration(
              icon: Icons.map_outlined,
              suffix: const Icon(
                Icons.expand_more_rounded,
                size: 22,
                color: AppColors.textMuted,
              ),
            ),
            child: Text(
              _state ?? 'Select your state',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: _state == null ? FontWeight.w400 : FontWeight.w600,
                color: _state == null
                    ? AppColors.textMuted
                    : AppColors.textDark,
              ),
            ),
          ),
        ),
        if (_submitted && _state == null)
          const _FieldError('State is required'),
      ],
    );
  }

  Widget _buildStorePicker() {
    return _Section(
      title: 'Your SHIELD store',
      subtitle: 'Allow location and pick your branch on the map. The nearest '
          'one is chosen for you — tap another pin or row to change it.',
      children: [
        StoreMapPicker(
          selectedId: _storeId,
          autoPickNearest: !_storePickedByHand,
          onLocationReady: (ready) {
            if (mounted && ready != _locationReady) {
              setState(() => _locationReady = ready);
            }
          },
          onSelected: (store) => setState(() {
            _storeId = store.id;
            _storePickedByHand = true;
          }),
        ),
        if (_submitted && !_locationReady)
          const _FieldError('Enable location to choose your SHIELD branch'),
        if (_submitted && _locationReady && _storeId == null)
          const _FieldError('Choose the branch you want to be served by'),
      ],
    );
  }

  Widget _buildActions() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              if (!widget.isEditing) ...[
                TextButton(
                  onPressed: _close,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  child: const Text(
                    'Skip for now',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    widget.isEditing
                        ? 'Save changes'
                        : 'Register & earn '
                              '${RegistrationService.rewardPoints} points',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The reward the form is offering, stated once at the top.
class _RewardNote extends StatelessWidget {
  const _RewardNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [AppColors.offerTint, AppColors.greenTint],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.stars_rounded,
              size: 22,
              color: AppColors.brandGreenDeep,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Register once and '
              '${RegistrationService.rewardPoints} reward points land on your '
              'account straight away.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: AppColors.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled white card holding one group of fields.
class _Section extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
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

/// Matches the message a `TextFormField` puts under a refused field, for the
/// controls that are not text fields and so have no validator of their own.
class _FieldError extends StatelessWidget {
  final String message;

  const _FieldError(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 2),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.danger,
        ),
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brandBlue : AppColors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.brandBlue : AppColors.border,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.white : AppColors.textBody,
            ),
          ),
        ),
      ),
    );
  }
}

/// One selectable branch.

/// Full-height list of states and union territories.
class _StatePicker extends StatelessWidget {
  final String? selected;

  const _StatePicker({required this.selected});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 10, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Select state',
                      style: TextStyle(
                        fontSize: 17.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textMuted,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: RegistrationService.states.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, index) {
                  final state = RegistrationService.states[index];
                  final isSelected = state == selected;
                  return ListTile(
                    onTap: () => Navigator.of(context).pop(state),
                    title: Text(
                      state,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: isSelected
                            ? AppColors.brandBlue
                            : AppColors.textDark,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: AppColors.brandBlue,
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
