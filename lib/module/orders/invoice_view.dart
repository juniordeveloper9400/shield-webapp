import 'package:flutter/material.dart';

import '../../dates.dart';
import '../../theme/app_colors.dart';
import 'bill_invoice.dart';

/// A store invoice laid out the way a printed one reads: seller, invoice
/// number and date, who it is billed to, every item with its quantity, price
/// and amount, then the totals and whether it is paid.
///
/// Pure display over a [BillInvoice] — nothing here reads a service — so the
/// member app and the web build draw the same document.
class InvoiceView extends StatelessWidget {
  final BillInvoice invoice;

  const InvoiceView({super.key, required this.invoice});

  static const _ink = AppColors.textDark;
  static const _muted = AppColors.textMuted;

  @override
  Widget build(BuildContext context) {
    final date = invoice.date;

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
          // --- Seller + invoice heading ---------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SHIELD Pharmacy',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandBlue,
                      ),
                    ),
                    if (invoice.storeName != 'SHIELD Pharmacy') ...[
                      const SizedBox(height: 2),
                      Text(
                        invoice.storeName,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                    ],
                    if (invoice.storeAddress.isNotEmpty)
                      Text(
                        invoice.storeAddress,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: _muted,
                        ),
                      ),
                    if (invoice.storePhone.isNotEmpty)
                      Text(
                        'Phone: ${invoice.storePhone}',
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'INVOICE',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _StatusChip(paid: invoice.paid),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),

          // --- Invoice details --------------------------------------------
          _Detail(label: 'Invoice no.', value: invoice.number, strong: true),
          if (date != null)
            _Detail(label: 'Invoice date', value: formatDateTime12h(date)),
          if (invoice.placedAt != null && invoice.billedAt != null)
            _Detail(
              label: 'Order placed',
              value: formatDateTime12h(invoice.placedAt!),
            ),
          _Detail(label: 'Order status', value: invoice.orderStatus),
          _Detail(
            label: 'Payment',
            value: invoice.paid
                ? (invoice.paidAt != null
                      ? 'Paid on ${formatDate(invoice.paidAt!)}'
                      : 'Paid')
                : 'Pending',
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),

          // --- Billed to / fulfilment -------------------------------------
          const _SectionLabel('BILLED TO'),
          const SizedBox(height: 4),
          Text(
            invoice.customerName.isEmpty
                ? 'SHIELD Member'
                : invoice.customerName,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          if (invoice.customerPhone.isNotEmpty)
            Text(
              invoice.customerPhone,
              style: const TextStyle(fontSize: 13, color: _muted),
            ),
          const SizedBox(height: 10),
          const _SectionLabel('FULFILMENT'),
          const SizedBox(height: 4),
          Text(
            invoice.fulfillment,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
          if (invoice.deliveryAddress.isNotEmpty)
            Text(
              invoice.deliveryAddress,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: _muted,
              ),
            ),
          const SizedBox(height: 14),

          // --- Items -------------------------------------------------------
          if (invoice.hasItems) ...[
            const _ItemsHeader(),
            for (final line in invoice.lines) _ItemRow(line: line),
            const SizedBox(height: 10),
            _TotalRow(label: 'Subtotal', paise: invoice.subtotalPaise),
            if (invoice.deliveryFeePaise != 0)
              _TotalRow(label: 'Delivery fee', paise: invoice.deliveryFeePaise),
            if (invoice.adjustmentPaise != 0)
              _TotalRow(
                label: 'Bill adjustment',
                paise: invoice.adjustmentPaise,
              ),
          ] else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.pageTint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'The store did not list the items on this bill. The total below '
                'is the amount that was billed.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: _muted),
              ),
            ),
          const SizedBox(height: 6),
          const Divider(height: 1, color: _ink),
          const SizedBox(height: 8),
          _TotalRow(label: 'TOTAL', paise: invoice.totalPaise, big: true),
          const SizedBox(height: 14),
          const Center(
            child: Text(
              'Thank you for choosing SHIELD Pharmacy.',
              style: TextStyle(fontSize: 12, color: _muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool paid;

  const _StatusChip({required this.paid});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: paid ? AppColors.greenTint : const Color(0xFFFDF3E0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        paid ? 'PAID' : 'PAYMENT PENDING',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: paid ? AppColors.brandGreenDark : const Color(0xFFB4761A),
        ),
      ),
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
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: AppColors.textMuted,
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _Detail({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const double _qtyWidth = 30;
const double _priceWidth = 76;
const double _amountWidth = 80;

class _ItemsHeader extends StatelessWidget {
  const _ItemsHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.3,
      color: AppColors.textMuted,
    );
    return Container(
      color: AppColors.pageTint,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: const Row(
        children: [
          Expanded(child: Text('ITEM', style: style)),
          SizedBox(
            width: _qtyWidth,
            child: Text('QTY', textAlign: TextAlign.right, style: style),
          ),
          SizedBox(
            width: _priceWidth,
            child: Text('PRICE', textAlign: TextAlign.right, style: style),
          ),
          SizedBox(
            width: _amountWidth,
            child: Text('AMOUNT', textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final InvoiceLine line;

  const _ItemRow({required this.line});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: AppColors.textDark,
                  ),
                ),
                if (line.pack.isNotEmpty)
                  Text(
                    line.pack,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: _qtyWidth,
            child: Text(
              '${line.qty}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, color: AppColors.textDark),
            ),
          ),
          SizedBox(
            width: _priceWidth,
            child: Text(
              formatPaise(line.unitPaise),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textDark),
            ),
          ),
          SizedBox(
            width: _amountWidth,
            child: Text(
              formatPaise(line.amountPaise),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final int paise;
  final bool big;

  const _TotalRow({required this.label, required this.paise, this.big = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: big ? 16 : 13,
      fontWeight: big ? FontWeight.w800 : FontWeight.w600,
      color: AppColors.textDark,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(formatPaise(paise), style: style),
        ],
      ),
    );
  }
}
