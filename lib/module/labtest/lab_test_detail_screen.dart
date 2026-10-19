import 'package:flutter/material.dart';

import '../../data/backend/care_repository.dart';
import '../../theme/app_colors.dart';
import 'lab_package.dart';

/// Test Details — opened by tapping a single test, either standalone or from
/// a package's "Included In The Package" list. Fetches the test's full
/// detail from `GET /v1/public/care/lab-tests/:id`
/// (`CareRepository.fetchLabTestDetail`).
class LabTestDetailScreen extends StatefulWidget {
  final String testId;

  const LabTestDetailScreen({super.key, required this.testId});

  @override
  State<LabTestDetailScreen> createState() => _LabTestDetailScreenState();
}

class _LabTestDetailScreenState extends State<LabTestDetailScreen> {
  late Future<LabTestDetail?> _future;

  @override
  void initState() {
    super.initState();
    _future = CareRepository.instance.fetchLabTestDetail(widget.testId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Test Details',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: FutureBuilder<LabTestDetail?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final test = snapshot.data;
          if (test == null) {
            return const Center(
              child: Text(
                "This test couldn't be loaded.",
                style: TextStyle(fontSize: 14.5, color: AppColors.textBody),
              ),
            );
          }
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              _DetailHeader(test: test),
              const SizedBox(height: 10),
              _DetailFactStrip(test: test),
              if (test.about.isNotEmpty) ...[
                const SizedBox(height: 10),
                _DetailTextBlock(title: 'About', body: test.about),
              ],
              if (test.whyThisTest.isNotEmpty) ...[
                const SizedBox(height: 10),
                _DetailTextBlock(
                  title: 'Why this test',
                  body: test.whyThisTest,
                ),
              ],
              if (test.symptoms.isNotEmpty) ...[
                const SizedBox(height: 10),
                _SymptomsBlock(symptoms: test.symptoms),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  final LabTestDetail test;

  const _DetailHeader({required this.test});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.offerTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.biotech_outlined,
              size: 32,
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    test.name,
                    style: const TextStyle(
                      fontSize: 19,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                  if (test.shortName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      test.shortName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailFactStrip extends StatelessWidget {
  final LabTestDetail test;

  const _DetailFactStrip({required this.test});

  @override
  Widget build(BuildContext context) {
    final effectiveReportOn = test.reportOn.isNotEmpty
        ? test.reportOn
        : test.reportingTime;
    final facts = [
      if (test.sample.isNotEmpty)
        _Fact(Icons.science_outlined, 'SAMPLE', test.sample),
      if (effectiveReportOn.isNotEmpty)
        _Fact(Icons.schedule_outlined, 'REPORT ON', effectiveReportOn),
      if (test.testMode.isNotEmpty)
        _Fact(Icons.biotech_outlined, 'TEST MODE', test.testMode),
      if (test.fasting.isNotEmpty)
        _Fact(Icons.no_food_outlined, 'FASTING', test.fasting),
    ];
    if (facts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final fact in facts)
            _FactTile(fact: fact),
        ],
      ),
    );
  }
}

class _Fact {
  final IconData icon;
  final String label;
  final String value;

  const _Fact(this.icon, this.label, this.value);
}

class _FactTile extends StatelessWidget {
  final _Fact fact;

  const _FactTile({required this.fact});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      decoration: BoxDecoration(
        color: AppColors.pageTint,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(fact.icon, size: 24, color: AppColors.textBody),
          const SizedBox(height: 12),
          Text(
            fact.label,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            fact.value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailTextBlock extends StatelessWidget {
  final String title;
  final String body;

  const _DetailTextBlock({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textBody,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Symptoms that may indicate this test" — chips entered on the Test
/// Master's "Why this test" tab, never hardcoded here.
class _SymptomsBlock extends StatelessWidget {
  final List<String> symptoms;

  const _SymptomsBlock({required this.symptoms});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Symptoms that may indicate this test',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final symptom in symptoms) _SymptomChip(symptom)],
          ),
        ],
      ),
    );
  }
}

class _SymptomChip extends StatelessWidget {
  final String label;

  const _SymptomChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textDark,
        ),
      ),
    );
  }
}
