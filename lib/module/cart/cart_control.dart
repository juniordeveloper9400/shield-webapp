import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;

import '../../theme/app_colors.dart';
import 'cart_service.dart';

/// The add-to-cart control used on every product tile.
///
/// A pale-blue **ADD** button until the line is in the cart, then a stepper
/// showing the quantity with a solid chevron cap that opens [_QuantityDialog].
/// Takes plain strings rather than a `Product` so both the home showcase and
/// the category listing can share it without a circular import.
class CartControl extends StatelessWidget {
  final String name;
  final String pack;
  final String price;
  final String mrp;

  /// Product artwork, passed straight through to the cart line so the basket
  /// shows the same picture as the tile.
  final String? image;

  const CartControl({
    super.key,
    required this.name,
    required this.pack,
    required this.price,
    required this.mrp,
    this.image,
  });

  // Fixtures carry formatted prices, so strip the grouping separator.
  double get _price => double.tryParse(price.replaceAll(',', '')) ?? 0;
  double get _mrp => double.tryParse(mrp.replaceAll(',', '')) ?? _price;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CartService.instance,
      builder: (context, _) {
        final cart = CartService.instance;
        final qty = cart.quantityFor(name);

        if (qty == 0) {
          return SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton(
              // Open to everyone: the cart is built up freely and the
              // account is only required at checkout.
              onPressed: () => cart.add(
                name: name,
                pack: pack,
                price: _price,
                mrp: _mrp,
                image: image,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandBlue,
                // Pale blue fill, not a hollow outline, so the call to action
                // reads at a glance in a grid of white tiles.
                backgroundColor: AppColors.panelBlue,
                side: const BorderSide(color: AppColors.brandBlue),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'ADD',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          );
        }

        return SizedBox(
          height: 40,
          child: Material(
            color: AppColors.panelBlue,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => _QuantityDialog.show(context, name: name),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.brandBlue, width: 1.2),
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: Text(
                          '$qty',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandBlue,
                          ),
                        ),
                      ),
                    ),
                    // Solid blue cap with the chevron: the affordance that
                    // tapping the control opens the quantity picker.
                    Container(
                      width: 46,
                      height: double.infinity,
                      color: AppColors.brandBlue,
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 24,
                        color: AppColors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The −/type/+ control for a cart line's quantity, shared by the product
/// tile's dialog and the cart screen's sheet.
///
/// Self-contained: it reads and writes [CartService] by line [name], clamps
/// every path to 1…[CartService.maxLineQty], and keeps the typed field in step
/// with the buttons without yanking it out from under an edit in progress.
class QuantityStepper extends StatefulWidget {
  final String name;

  const QuantityStepper({super.key, required this.name});

  @override
  State<QuantityStepper> createState() => _QuantityStepperState();
}

class _QuantityStepperState extends State<QuantityStepper> {
  static const int _max = CartService.maxLineQty;

  final _field = TextEditingController();
  final _focus = FocusNode();

  int get _current => CartService.instance.quantityFor(widget.name);

  @override
  void initState() {
    super.initState();
    _field.text = '${_current.clamp(1, _max)}';
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setQty(int qty) =>
      CartService.instance.setQty(widget.name, qty.clamp(1, _max));

  /// Reads whatever was typed, clamps it, writes it back, and reverts the text
  /// to the accepted value.
  void _commitTyped() {
    final typed = int.tryParse(_field.text.trim());
    final next = (typed ?? _current).clamp(1, _max);
    _setQty(next);
    _field.text = '$next';
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CartService.instance,
      builder: (context, _) {
        final selected = _current.clamp(1, _max);
        if (!_focus.hasFocus && _field.text != '$selected') {
          _field.text = '$selected';
        }

        return Column(
          children: [
            Row(
              children: [
                _StepButton(
                  icon: Icons.remove_rounded,
                  onTap: selected > 1 ? () => _setQty(selected - 1) : null,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: _field,
                      focusNode: _focus,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      onSubmitted: (_) => _commitTyped(),
                      onTapOutside: (_) {
                        if (_focus.hasFocus) {
                          _commitTyped();
                        }
                      },
                      onEditingComplete: _commitTyped,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandBlue,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppColors.brandBlue,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _StepButton(
                  icon: Icons.add_rounded,
                  onTap: selected < _max ? () => _setQty(selected + 1) : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Type any amount up to $_max, or pick one below',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        );
      },
    );
  }
}

/// Opens the shared centred "Select quantity" dialog for the cart line named
/// [name]. This is the one picker used everywhere — the product cards, the home
/// showcases and the cart screen — so the quantity control looks and behaves
/// the same wherever it is reached from.
Future<void> showCartQuantityDialog(
  BuildContext context, {
  required String name,
}) {
  return _QuantityDialog.show(context, name: name);
}

/// Centred dialog for changing the quantity of a line already in the cart.
///
/// A [QuantityStepper] at the top — which types or steps up to
/// [CartService.maxLineQty] — over a radio list of the first
/// [CartService.quickPickQty] quantities, with a "Remove item" row beneath. The
/// stepper edits the line in place; a tap on a list row picks it and closes.
class _QuantityDialog extends StatelessWidget {
  final String name;

  const _QuantityDialog({required this.name});

  static Future<void> show(BuildContext context, {required String name}) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _QuantityDialog(name: name),
    );
  }

  static const int _max = CartService.maxLineQty;

  /// The shortcut list runs to here; larger amounts are typed in the stepper.
  static const int _listMax = CartService.quickPickQty;

  @override
  Widget build(BuildContext context) {
    void pick(int qty) {
      CartService.instance.setQty(name, qty.clamp(1, _max));
      Navigator.of(context).pop();
    }

    return Dialog(
      backgroundColor: AppColors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 44, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: ListenableBuilder(
          listenable: CartService.instance,
          builder: (context, _) {
            final current = CartService.instance.quantityFor(name);
            // Briefly true between "Remove item" writing 0 and the dialog
            // popping itself.
            if (current == 0) {
              return const SizedBox.shrink();
            }
            final selected = current.clamp(1, _max);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Select quantity',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      _CloseButton(onTap: () => Navigator.of(context).pop()),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: QuantityStepper(name: name),
                ),
                const Divider(height: 1, color: AppColors.border),
                Flexible(
                  // Capped so the dialog stays a small centred card — about
                  // four rows show and the rest of the list scrolls inside
                  // this window rather than stretching the card down the page.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: RadioGroup<int>(
                        groupValue: selected,
                        onChanged: (qty) {
                          if (qty != null) {
                            pick(qty);
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var qty = 1; qty <= _listMax; qty++) ...[
                              _QuantityRow(
                                quantity: qty,
                                selectedQuantity: selected,
                                onTap: () => pick(qty),
                              ),
                              if (qty != _listMax)
                                const Divider(
                                  height: 1,
                                  color: AppColors.border,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                InkWell(
                  onTap: () {
                    CartService.instance.setQty(name, 0);
                    Navigator.of(context).pop();
                  },
                  child: const SizedBox(
                    height: 52,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.danger,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Remove item',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A square −/+ button for the quantity stepper. Greyed out when [onTap] is
/// null (at the floor or the ceiling).
class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? AppColors.panelBlue : AppColors.pageTint,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled ? AppColors.brandBlue : AppColors.border,
              width: 1.2,
            ),
          ),
          child: Icon(
            icon,
            size: 22,
            color: enabled ? AppColors.brandBlue : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      shape: const CircleBorder(
        side: BorderSide(color: Color(0xFFB8C1CC), width: 1.2),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 32,
          height: 32,
          child: Icon(Icons.close_rounded, size: 19, color: AppColors.textDark),
        ),
      ),
    );
  }
}

class _QuantityRow extends StatelessWidget {
  final int quantity;
  final int selectedQuantity;
  final VoidCallback onTap;

  const _QuantityRow({
    required this.quantity,
    required this.selectedQuantity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedQuantity == quantity;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 50,
        color: isSelected ? AppColors.pageTint : AppColors.white,
        padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$quantity',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textDark,
                ),
              ),
            ),
            Radio<int>(
              value: quantity,
              activeColor: AppColors.brandBlue,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}
