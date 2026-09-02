// Seeds the reference & content tables of the "app" schema with the data the
// Flutter app currently hard-codes in lib/module/*.
//
//   dart run backend/db/seed_app.dart            # dry run
//   dart run backend/db/seed_app.dart --yes      # insert
//
// Run AFTER apply_app_schema.dart. Safe to re-run only on a freshly applied
// schema — it inserts, it does not upsert.
//
// What it loads:
//   * shield_store        — the 10 branches from StoreDirectory
//   * membership_tier(+loads) — Silver / Gold / Platinum and their fixed loads
//   * referral_level      — the 5-rung refer-and-earn ladder
//   * payment_method      — the checkout methods (only bank transfer is live)
//   * product_category    — the storefront category tabs
//   * lab_package         — a representative slice of the lab catalogue
//   * clinic / dietitian / health_article / promo — sample home-feed content
//
// The full product / lab / article catalogues live in Dart files that import
// Flutter (IconData, Color) and cannot be read from a plain `dart run`. Load
// the rest through the admin tool or extend this file.

import 'dart:io';

import 'package:postgres/postgres.dart';

Future<void> main(List<String> args) async {
  final confirmed = args.contains('--yes');

  final url = _databaseUrl();
  if (url == null || url.isEmpty) {
    stderr.writeln('DATABASE_URL not found (env or .env at repo root).');
    exit(1);
  }

  final uri = Uri.parse(url);
  final ui = uri.userInfo.split(':');
  final conn = await Connection.open(
    Endpoint(
      host: uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'neondb',
      username: Uri.decodeComponent(ui.first),
      password: ui.length > 1 ? Uri.decodeComponent(ui[1]) : null,
    ),
    settings: const ConnectionSettings(
      sslMode: SslMode.require,
      applicationName: 'shield-app-seed',
    ),
  );

  final hasSchema = (await conn.execute(
    "select count(*) from information_schema.schemata where schema_name = 'app'",
  )).first.first as int;
  if (hasSchema == 0) {
    stderr.writeln('Schema "app" does not exist. Run apply_app_schema.dart first.');
    await conn.close();
    exit(1);
  }

  if (!confirmed) {
    stdout
      ..writeln('Dry run — would seed:')
      ..writeln('  shield_store        10')
      ..writeln('  membership_tier      3  (+ 10 loads)')
      ..writeln('  referral_level       5')
      ..writeln('  payment_method       4')
      ..writeln('  product_category     6')
      ..writeln('  lab_package          5')
      ..writeln('  clinic               3')
      ..writeln('  dietitian            3')
      ..writeln('  health_article       3')
      ..writeln('  promo                3')
      ..writeln('\nRe-run with --yes to insert.');
    await conn.close();
    return;
  }

  await conn.execute('SET search_path TO app, public', queryMode: QueryMode.simple);
  await conn.runTx((tx) async {
    await _seedStores(tx);
    await _seedTiers(tx);
    await _seedReferralLevels(tx);
    await _seedPaymentMethods(tx);
    await _seedCategories(tx);
    await _seedSubcategories(tx);
    await _seedLabPackages(tx);
    await _seedClinics(tx);
    await _seedDietitians(tx);
    await _seedArticles(tx);
    await _seedPromos(tx);
  });

  final counts = <String, int>{};
  for (final t in [
    'shield_store',
    'membership_tier',
    'membership_tier_load',
    'referral_level',
    'payment_method',
    'product_category',
    'lab_package',
    'lab_profile',
    'clinic',
    'clinic_doctor',
    'dietitian',
    'health_article',
    'promo',
  ]) {
    counts[t] = (await conn.execute('select count(*) from app.$t')).first.first as int;
  }
  stdout.writeln('\nSeeded:');
  counts.forEach((t, n) => stdout.writeln('  ${t.padRight(24)} $n'));

  await conn.close();
}

// --- shield_store -----------------------------------------------------------
Future<void> _seedStores(TxSession tx) async {
  const rows = [
    ['SHD-MEL', 'SHIELD Pharmacy Melattur', 'Melattur', 'Malappuram', '679326'],
    ['SHD-MKP', 'SHIELD Pharmacy Makkaraparamba', 'Makkaraparamba', 'Malappuram', '676507'],
    ['SHD-TIR', 'SHIELD Pharmacy Tirur', 'Tirur', 'Malappuram', '676101'],
    ['SHD-KKT', 'SHIELD Pharmacy Karinkallathani', 'Karinkallathani', 'Malappuram', '679321'],
    ['SHD-MJR', 'SHIELD Pharmacy Manjery', 'Manjery', 'Malappuram', '676121'],
    ['SHD-ALN', 'SHIELD Pharmacy Alanallur', 'Alanallur', 'Palakkad', '678601'],
    ['SHD-TRD', 'SHIELD Pharmacy Tirurangadi', 'Tirurangadi', 'Malappuram', '676306'],
    ['SHD-KNP', 'SHIELD Pharmacy Kunnumpuram', 'Kunnumpuram', 'Malappuram', '676505'],
    ['SHD-KND', 'SHIELD Pharmacy Kondotty', 'Kondotty', 'Malappuram', '673638'],
    ['SHD-ARK', 'SHIELD Pharmacy Areekode', 'Areekode', 'Malappuram', '673639'],
  ];
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    await tx.execute(
      Sql.named('insert into app.shield_store (code,name,area,city,state,pincode,sort) '
          'values (@c,@n,@a,@ci,@s,@p,@so)'),
      parameters: {'c': r[0], 'n': r[1], 'a': r[2], 'ci': r[3], 's': 'Kerala', 'p': r[4], 'so': i},
    );
  }
}

// --- membership_tier + loads ----------------------------------------------
Future<void> _seedTiers(TxSession tx) async {
  const tiers = [
    ['SILVER', 'Silver Shield', '9010', 'A year of routine refills for one person.',
      [10000, 20000, 30000]],
    ['GOLD', 'Gold Shield', '9020', 'A family on long-term medication, with room for lab tests.',
      [40000, 50000]],
    ['PLATINUM', 'Platinum Shield', '9030', 'Chronic care across several patients, up to a lakh.',
      [60000, 70000, 80000, 90000, 100000]],
  ];
  for (var i = 0; i < tiers.length; i++) {
    final t = tiers[i];
    final id = (await tx.execute(
      Sql.named('insert into app.membership_tier (kind,name,bin,blurb,sort) '
          'values (@k,@n,@b,@bl,@s) returning id'),
      parameters: {'k': t[0], 'n': t[1], 'b': t[2], 'bl': t[3], 's': i},
    )).first.first as int;
    final loads = t[4] as List<int>;
    for (var j = 0; j < loads.length; j++) {
      await tx.execute(
        Sql.named('insert into app.membership_tier_load (tier_id,amount,sort) '
            'values (@t,@a,@s)'),
        parameters: {'t': id, 'a': loads[j], 's': j},
      );
    }
  }
}

// --- referral_level ------------------------------------------------------
Future<void> _seedReferralLevels(TxSession tx) async {
  const rows = [
    [1, 'Starter', 2, 100],
    [2, 'Riser', 5, 200],
    [3, 'Achiever', 10, 500],
    [4, 'Champion', 20, 1500],
    [5, 'Legend', 40, 3000],
  ];
  for (final r in rows) {
    await tx.execute(
      Sql.named('insert into app.referral_level (level,name,referrals_required,points) '
          'values (@l,@n,@r,@p)'),
      parameters: {'l': r[0], 'n': r[1], 'r': r[2], 'p': r[3]},
    );
  }
}

// --- payment_method ----------------------------------------------------
Future<void> _seedPaymentMethods(TxSession tx) async {
  const rows = [
    ['bank-transfer', 'Bank account', 'Pay by UPI or bank transfer, upload the receipt', true, 0],
    ['gpay', 'Google Pay', 'Coming soon', false, 1],
    ['phonepe', 'PhonePe', 'Coming soon', false, 2],
    ['paytm', 'Paytm', 'Coming soon', false, 3],
  ];
  for (final r in rows) {
    await tx.execute(
      Sql.named('insert into app.payment_method (code,name,blurb,is_live,sort) '
          'values (@c,@n,@b,@l,@s)'),
      parameters: {'c': r[0], 'n': r[1], 'b': r[2], 'l': r[3], 's': r[4]},
    );
  }
}

// --- product_category -------------------------------------------------
Future<void> _seedCategories(TxSession tx) async {
  const rows = [
    ['personal-care', 'Personal Care', 'Personal Care', 'Up to 25% off'],
    ['health-conditions', 'Health Conditions', 'Health Conditions', ''],
    ['vitamins-supplements', 'Vitamins & Supplements', 'Vitamins & Supplements', 'Up to 20% off'],
    ['diabetes-care', 'Diabetes Care', 'Diabetes Care', 'Up to 30% off'],
    ['surgicals', 'Surgicals', 'Surgicals', ''],
    ['lab-tests', 'Lab Tests', 'Lab Tests', 'Up to 60% off'],
  ];
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    await tx.execute(
      Sql.named('insert into app.product_category (slug,title,tab_label,offer,sort) '
          'values (@sl,@t,@tl,@o,@s)'),
      parameters: {'sl': r[0], 't': r[1], 'tl': r[2], 'o': r[3], 's': i},
    );
  }
}

// --- product_subcategory --------------------------------------------
// Word-for-word the sub-categories in the app's category browser
// (lib/module/categories/category_catalogue.dart) — the app matches on label.
// Migration 0004 seeds the same set onto an already-populated database.
Future<void> _seedSubcategories(TxSession tx) async {
  const rows = <List<String>>[
    ['personal-care', 'Skin Care'],
    ['personal-care', 'Hair Care'],
    ['personal-care', 'Oral Care'],
    ['personal-care', 'Bath & Body'],
    ['personal-care', 'Men Grooming'],
    ['personal-care', 'Feminine Care'],
    ['health-conditions', 'Bone and Joint Care'],
    ['health-conditions', 'Digestive Care'],
    ['health-conditions', 'Eye Care'],
    ['health-conditions', 'Pain Relief'],
    ['health-conditions', 'Smoking Cessation'],
    ['health-conditions', 'Liver Care'],
    ['vitamins-supplements', 'Multivitamins'],
    ['vitamins-supplements', 'Vitamin D'],
    ['vitamins-supplements', 'Protein Powder'],
    ['vitamins-supplements', 'Omega & Fish Oil'],
    ['vitamins-supplements', 'Calcium'],
    ['vitamins-supplements', 'Immunity'],
    ['diabetes-care', 'Glucometers'],
    ['diabetes-care', 'Test Strips'],
    ['diabetes-care', 'Sugar Substitutes'],
    ['diabetes-care', 'Diabetic Food'],
    ['diabetes-care', 'Foot Care'],
    ['diabetes-care', 'Insulin Support'],
    ['surgicals', 'Gloves & Masks'],
    ['surgicals', 'Bandages & Dressings'],
    ['surgicals', 'Syringes & Needles'],
    ['surgicals', 'Supports & Braces'],
    ['surgicals', 'First Aid Kits'],
    ['surgicals', 'Mobility Aids'],
    ['lab-tests', 'Full Body Checkup'],
    ['lab-tests', 'Blood Tests'],
    ['lab-tests', 'Thyroid Profile'],
    ['lab-tests', 'Vitamin Tests'],
  ];
  var sort = 0;
  String? prevCat;
  for (final r in rows) {
    if (r[0] != prevCat) {
      sort = 0;
      prevCat = r[0];
    }
    await tx.execute(
      Sql.named(
        'insert into app.product_subcategory (category_id,label,sort) '
        'select id, @label, @sort from app.product_category where slug = @slug',
      ),
      parameters: {'slug': r[0], 'label': r[1], 'sort': sort},
    );
    sort++;
  }
}

// --- lab_package (representative) ------------------------------------
Future<void> _seedLabPackages(TxSession tx) async {
  const rows = [
    ['full-body-checkup', 'Full Body Checkup', 92, 9, '4.8', '12k+ booked', '24 hrs', 999, 2499, 1500],
    ['diabetes-screening', 'Diabetes Screening', 14, 2, '4.7', '8k+ booked', '12 hrs', 499, 1199, 700],
    ['thyroid-profile', 'Thyroid Profile (T3 T4 TSH)', 3, 1, '4.7', '20k+ booked', '12 hrs', 349, 799, 450],
    ['heart-health', 'Heart Health Panel', 32, 4, '4.6', '5k+ booked', '24 hrs', 1299, 2999, 1700],
    ['vitamin-panel', 'Vitamin D + B12', 2, 1, '4.8', '15k+ booked', '24 hrs', 899, 1999, 1100],
  ];
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    await tx.execute(
      Sql.named('insert into app.lab_package '
          '(slug,name,test_count,profile_count,rating,booked,report_in,price,mrp,saved,sort) '
          'values (@sl,@n,@tc,@pc,@ra,@bk,@ri,@pr,@mr,@sv,@so)'),
      parameters: {
        'sl': r[0], 'n': r[1], 'tc': r[2], 'pc': r[3], 'ra': r[4], 'bk': r[5],
        'ri': r[6], 'pr': r[7], 'mr': r[8], 'sv': r[9], 'so': i,
      },
    );
  }
}

// --- clinic (sample) ----------------------------------------------
Future<void> _seedClinics(TxSession tx) async {
  const rows = [
    ['SHIELD Dental Care, Melattur', 'Dental', 'Melattur, Malappuram', '+91 90000 11111', true],
    ['SHIELD Family Clinic, Manjery', 'Multi-speciality', 'Manjery, Malappuram', '+91 90000 22222', true],
    ['SHIELD Tele-Consult', 'Tele-consultation', 'Online', '', false],
  ];
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final id = (await tx.execute(
      Sql.named('insert into app.clinic (name,type,location,phone,is_verified,sort) '
          'values (@n,@t,@l,@p,@v,@s) returning id'),
      parameters: {'n': r[0], 't': r[1], 'l': r[2], 'p': r[3], 'v': r[4], 's': i},
    )).first.first as int;
    await tx.execute(
      Sql.named('insert into app.clinic_doctor (clinic_id,name,speciality,fee,sort) '
          'values (@c,@n,@sp,@f,0)'),
      parameters: {'c': id, 'n': 'Dr. A. Menon', 'sp': r[1], 'f': '₹300'},
    );
  }
}

// --- dietitian (sample) -----------------------------------------
Future<void> _seedDietitians(TxSession tx) async {
  const rows = [
    ['Layla Rahman', 'MSc Clinical Nutrition', 5, 500, 'Today, 4:00 PM'],
    ['Anjana Pillai', 'RD, Diabetes Educator', 8, 600, 'Tomorrow, 11:00 AM'],
    ['Faisal K', 'MSc Food & Nutrition', 3, 400, 'Today, 6:30 PM'],
  ];
  final focus = _pgArray(['Weight management', 'Diabetes']);
  final langs = _pgArray(['Malayalam', 'English']);
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    await tx.execute(
      Sql.named('insert into app.dietitian '
          '(name,qualification,experience_years,fee,next_slot,focus,languages,sort) '
          'values (@n,@q,@e,@f,@ns,$focus,$langs,@s)'),
      parameters: {
        'n': r[0], 'q': r[1], 'e': r[2], 'f': r[3], 'ns': r[4], 's': i,
      },
    );
  }
}

// --- health_article (sample) ----------------------------------
Future<void> _seedArticles(TxSession tx) async {
  const rows = [
    ['managing-blood-sugar', 'Managing Blood Sugar Day to Day', 'Dr. Anjana Pillai'],
    ['reading-a-lab-report', 'How to Read Your Lab Report', 'SHIELD Health Desk'],
    ['generic-vs-branded', 'Generic vs Branded Medicine', 'SHIELD Pharmacy Team'],
  ];
  final topics = _pgArray(['Wellness']);
  final paragraphs = _pgArray(['Body copy goes here.']);
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final intro = _pgArray(['A short introduction to ${r[1]}.']);
    final id = (await tx.execute(
      Sql.named('insert into app.health_article (slug,title,author,topics,intro,sort) '
          'values (@sl,@t,@au,$topics,$intro,@s) returning id'),
      parameters: {'sl': r[0], 't': r[1], 'au': r[2], 's': i},
    )).first.first as int;
    await tx.execute(
      Sql.named('insert into app.health_article_section (article_id,sort,heading,paragraphs) '
          'values (@a,0,@h,$paragraphs)'),
      parameters: {'a': id, 'h': 'Overview'},
    );
  }
}

/// A Postgres `text[]` literal for a list of our own constant strings,
/// e.g. `ARRAY['a','b']::text[]`. Single quotes are doubled; these values are
/// hard-coded here, never user input.
String _pgArray(List<String> values) {
  if (values.isEmpty) return "ARRAY[]::text[]";
  final parts = values.map((v) => "'${v.replaceAll("'", "''")}'").join(',');
  return 'ARRAY[$parts]::text[]';
}

// --- promo (sample) ------------------------------------------
Future<void> _seedPromos(TxSession tx) async {
  const rows = [
    ['Get', 'flat', '20%', 'off your first order', 'Shop now', 'SHIELD20', '20%'],
    ['Save on', 'lab', 'tests', 'up to 60% off', 'Book a test', 'LAB60', '60%'],
    ['Refer', 'and', 'earn', 'points on every invite', 'Invite friends', '', ''],
  ];
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    await tx.execute(
      Sql.named('insert into app.promo '
          '(title_top,title_middle,title_accent,title_tail,cta,code,percent,sort) '
          'values (@tt,@tm,@ta,@tl,@c,@co,@pe,@s)'),
      parameters: {
        'tt': r[0], 'tm': r[1], 'ta': r[2], 'tl': r[3], 'c': r[4],
        'co': r[5], 'pe': r[6], 's': i,
      },
    );
  }
}

String? _databaseUrl() {
  final env = Platform.environment['DATABASE_URL'];
  if (env != null && env.isNotEmpty) return env;
  final file = File('.env');
  if (!file.existsSync()) return null;
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq <= 0 || line.substring(0, eq).trim() != 'DATABASE_URL') continue;
    var v = line.substring(eq + 1).trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    return v;
  }
  return null;
}
