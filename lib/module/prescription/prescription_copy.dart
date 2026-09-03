import 'package:flutter/foundation.dart';

/// The languages the prescription flow is written in.
///
/// Scoped to this screen rather than the app. SHIELD's counters are in Kerala
/// and this is the screen a member reads instructions on — the rest of the app
/// is names, prices and buttons, which need no translating to be usable.
enum AppLanguage {
  english('English', 'ENG'),
  malayalam('മലയാളം', 'മ');

  /// The full name, written in the language itself. Not drawn on the switch —
  /// it is what a screen reader is given, where "ENG" would be read out as
  /// three letters.
  final String label;

  /// What the switch shows. Two buttons of full names crowd the top of the
  /// screen and push the heading down; the codes say the same thing in a
  /// third of the width. Malayalam's is its own letter rather than a
  /// romanisation — a reader looking for their language looks for the script.
  final String code;

  const AppLanguage(this.label, this.code);

  AppLanguage get other =>
      this == english ? AppLanguage.malayalam : AppLanguage.english;
}

/// One numbered step of the ordering procedure.
@immutable
class OrderStep {
  final String title;
  final String detail;

  const OrderStep(this.title, this.detail);
}

/// Every string the upload screen writes, in one language.
///
/// A table rather than a lookup by key: a missing key would compile and then
/// show a blank line, while a missing field will not compile at all.
@immutable
class PrescriptionCopy {
  final String heading;
  final String intro;
  final String useCamera;
  final String useGallery;
  final String patientLabel;
  final String patientHint;
  final String durationHeading;
  final String durationIntro;
  final String customDays;
  final String customDaysHint;
  final String keepInMind;
  final List<String> rules;
  final String howToOrder;
  final String howToOrderIntro;
  final List<OrderStep> steps;
  final String pharmacistTitle;
  final String pharmacistDetail;
  final String free;
  final String proceed;
  final String remove;
  final String viewFile;

  // ---- Recurring orders ----
  final String recurringHeading;
  final String recurringIntro;
  final String recurringToggle;
  final String fromDate;
  final String dueDate;
  final String neverExpires;
  final String selectDate;
  final String dueBeforeFrom;

  // ---- The list of uploaded prescriptions ----
  final String yourPrescriptions;
  final String yourPrescriptionsIntro;
  final String newPrescription;
  final String addPrescription;
  final String addNewPrescription;

  // ---- Delivery details ----
  final String deliveryDetails;
  final String deliveryDetailsIntro;
  final String noDeliveryAddress;
  final String addDeliveryAddress;
  final String changeAddress;
  final String patientRow;
  final String doctorRow;
  final String doctorHint;
  final String repeatsRow;

  // ---- The medicine table on each card ----
  final String product;
  final String intake;
  final String total;
  final String intakeHelp;
  final String awaitingReview;
  final String awaitingReviewDetail;

  /// Morning, afternoon, night — in that order, because an intake code is
  /// read left to right and the labels have to line up with the digits.
  final List<String> intakeSlots;

  final String intakeNotSet;
  final String units;
  final String addToCart;
  final String inCart;
  final String delete;
  final String prescriptionRemoved;
  final String undo;
  final String sentToCart;

  // ---- Order-first flow ----
  final String proceedToDelivery;
  final String beforeOrderNote;
  final String orderPlacedTitle;
  final String orderPlacedDetail;
  final String intakeCardReady;
  final String viewMedicines;
  final String hideMedicines;
  final String medicineSingular;
  final String medicinePlural;

  const PrescriptionCopy({
    required this.heading,
    required this.intro,
    required this.useCamera,
    required this.useGallery,
    required this.patientLabel,
    required this.patientHint,
    required this.durationHeading,
    required this.durationIntro,
    required this.customDays,
    required this.customDaysHint,
    required this.keepInMind,
    required this.rules,
    required this.howToOrder,
    required this.howToOrderIntro,
    required this.steps,
    required this.pharmacistTitle,
    required this.pharmacistDetail,
    required this.free,
    required this.proceed,
    required this.remove,
    required this.viewFile,
    required this.recurringHeading,
    required this.recurringIntro,
    required this.recurringToggle,
    required this.fromDate,
    required this.dueDate,
    required this.neverExpires,
    required this.selectDate,
    required this.dueBeforeFrom,
    required this.yourPrescriptions,
    required this.yourPrescriptionsIntro,
    required this.newPrescription,
    required this.addPrescription,
    required this.addNewPrescription,
    required this.deliveryDetails,
    required this.deliveryDetailsIntro,
    required this.noDeliveryAddress,
    required this.addDeliveryAddress,
    required this.changeAddress,
    required this.patientRow,
    required this.doctorRow,
    required this.doctorHint,
    required this.repeatsRow,
    required this.product,
    required this.intake,
    required this.total,
    required this.intakeHelp,
    required this.awaitingReview,
    required this.awaitingReviewDetail,
    required this.intakeSlots,
    required this.intakeNotSet,
    required this.units,
    required this.addToCart,
    required this.inCart,
    required this.delete,
    required this.prescriptionRemoved,
    required this.undo,
    required this.sentToCart,
    required this.proceedToDelivery,
    required this.beforeOrderNote,
    required this.orderPlacedTitle,
    required this.orderPlacedDetail,
    required this.intakeCardReady,
    required this.viewMedicines,
    required this.hideMedicines,
    required this.medicineSingular,
    required this.medicinePlural,
  });

  static PrescriptionCopy of(AppLanguage language) =>
      language == AppLanguage.malayalam ? malayalam : english;

  static const PrescriptionCopy english = PrescriptionCopy(
    heading: 'Upload your prescription to start ordering',
    intro:
        'Please ensure that the prescription is valid and contains doctor, '
        'patient and medicine details.',
    useCamera: 'Use\nCamera',
    useGallery: 'Use\nGallery',
    patientLabel: 'Prescription is for',
    patientHint: 'Select patient',
    durationHeading: 'How much do you need?',
    durationIntro:
        'We dispense up to this much, or up to what the prescription '
        'allows — whichever is less.',
    customDays: 'Custom days',
    customDaysHint: 'Enter number of days',
    keepInMind: 'Please keep in mind:',
    rules: [
      'Prescription should be valid and contains, doctor, patient, date '
          'and medicine details',
      'Supported formats: JPG, JPEG, PNG, PDF, WebP, HEIF and HEIC',
      'File size must be under 5 MB',
    ],
    howToOrder: 'How to order your medicine',
    howToOrderIntro: 'Five steps, from the prescription to your door.',
    steps: [
      OrderStep(
        'Upload the prescription',
        'Photograph it or pick a file. No prescription to hand? Call your '
            'nearest store instead.',
      ),
      OrderStep(
        'Say who it is for',
        'Choose the patient and how many days of medicine you need.',
      ),
      OrderStep(
        'A pharmacist checks it',
        'We read the prescription and call you to confirm the medicines.',
      ),
      OrderStep(
        'Confirm and pay',
        'Pay from your wallet, online, or in cash when the order arrives.',
      ),
      OrderStep(
        'Delivered, or collect it',
        'We deliver to your address, or hold it at your SHIELD store.',
      ),
    ],
    pharmacistTitle: 'Pharmacist call',
    pharmacistDetail:
        'Our pharmacist will call to confirm the medicines in your '
        'prescription',
    free: 'Free',
    proceed: 'Proceed',
    remove: 'Remove',
    viewFile: 'View',
    recurringHeading: 'Recurring order',
    recurringIntro:
        'For medicine you take every month. We reorder it for you until the '
        'due date, or until you stop it.',
    recurringToggle: 'Repeat this prescription',
    fromDate: 'From date',
    dueDate: 'Due date',
    neverExpires: 'Never expires',
    selectDate: 'Select date',
    dueBeforeFrom: 'The due date must come after the from date.',
    yourPrescriptions: 'Your prescriptions',
    yourPrescriptionsIntro:
        'Place the order and the pharmacist reads your prescription, calls '
        'you, and sends the medicine list back to this card.',
    newPrescription: 'New prescription',
    addPrescription: 'Add prescription',
    addNewPrescription: 'Add new prescription',
    deliveryDetails: 'Delivery details',
    deliveryDetailsIntro:
        'Where the pharmacist sends the order once you confirm it on the '
        'call.',
    noDeliveryAddress: 'No delivery address yet',
    addDeliveryAddress: 'Add delivery address',
    changeAddress: 'Change',
    patientRow: 'Patient',
    doctorRow: 'Doctor',
    doctorHint: "Doctor's name",
    repeatsRow: 'Repeats',
    product: 'Product',
    intake: 'Intake',
    total: 'Total',
    intakeHelp:
        'Three digits — morning, afternoon, night. 101 is one in the morning '
        'and one at night; 110 is morning and afternoon; 001 is night only.',
    awaitingReview: 'Our pharmacist is reading this prescription',
    awaitingReviewDetail:
        'The medicines and the intake will appear here once the '
        'counter has checked it, usually within a few minutes.',
    intakeSlots: ['Morning', 'Afternoon', 'Night'],
    intakeNotSet: 'Not set',
    units: 'units',
    addToCart: 'Add to cart',
    inCart: 'In cart',
    delete: 'Delete',
    prescriptionRemoved: 'Prescription removed',
    undo: 'Undo',
    sentToCart: 'sent to the cart',
    proceedToDelivery: 'Proceed to delivery',
    beforeOrderNote:
        'Place the order below. The pharmacist then reads the script and '
        'builds the medicine list for you.',
    orderPlacedTitle: 'Order placed',
    orderPlacedDetail:
        'The pharmacist will call you to confirm the medicines and the '
        'price. This card fills in once they send the details.',
    intakeCardReady: 'Intake card ready',
    viewMedicines: 'View medicines',
    hideMedicines: 'Hide',
    medicineSingular: 'medicine',
    medicinePlural: 'medicines',
  );

  static const PrescriptionCopy malayalam = PrescriptionCopy(
    heading: 'ഓർഡർ ചെയ്യാൻ നിങ്ങളുടെ കുറിപ്പടി അപ്‌ലോഡ് ചെയ്യുക',
    intro:
        'കുറിപ്പടി സാധുവാണെന്നും അതിൽ ഡോക്ടർ, രോഗി, മരുന്ന് എന്നിവയുടെ '
        'വിവരങ്ങൾ ഉണ്ടെന്നും ഉറപ്പാക്കുക.',
    useCamera: 'ക്യാമറ\nഉപയോഗിക്കുക',
    useGallery: 'ഗാലറി\nഉപയോഗിക്കുക',
    patientLabel: 'കുറിപ്പടി ആർക്കുവേണ്ടി',
    patientHint: 'രോഗിയെ തിരഞ്ഞെടുക്കുക',
    durationHeading: 'എത്ര ദിവസത്തേക്ക് വേണം?',
    durationIntro:
        'ഇത്രയും വരെ, അല്ലെങ്കിൽ കുറിപ്പടി അനുവദിക്കുന്നത്ര — ഇതിൽ ഏതാണോ '
        'കുറവ്, അത്രയും ഞങ്ങൾ നൽകും.',
    customDays: 'ദിവസം നൽകുക',
    customDaysHint: 'എത്ര ദിവസമെന്ന് ടൈപ്പ് ചെയ്യുക',
    keepInMind: 'ശ്രദ്ധിക്കുക:',
    rules: [
      'കുറിപ്പടി സാധുവായിരിക്കണം; ഡോക്ടർ, രോഗി, തീയതി, മരുന്ന് എന്നിവയുടെ '
          'വിവരങ്ങൾ അതിൽ ഉണ്ടായിരിക്കണം',
      'സ്വീകരിക്കുന്ന ഫോർമാറ്റുകൾ: JPG, JPEG, PNG, PDF, WebP, HEIF, HEIC',
      'ഫയലിന്റെ വലുപ്പം 5 MB-യിൽ കുറവായിരിക്കണം',
    ],
    howToOrder: 'മരുന്ന് ഓർഡർ ചെയ്യുന്ന വിധം',
    howToOrderIntro: 'കുറിപ്പടി മുതൽ വീട്ടുപടി വരെ, അഞ്ച് ഘട്ടങ്ങൾ.',
    steps: [
      OrderStep(
        'കുറിപ്പടി അപ്‌ലോഡ് ചെയ്യുക',
        'ഫോട്ടോ എടുക്കുക അല്ലെങ്കിൽ ഫയൽ തിരഞ്ഞെടുക്കുക. കുറിപ്പടി '
            'ഇല്ലെങ്കിൽ അടുത്തുള്ള സ്റ്റോറിലേക്ക് വിളിക്കുക.',
      ),
      OrderStep(
        'ആർക്കുവേണ്ടിയെന്ന് അറിയിക്കുക',
        'രോഗിയെയും എത്ര ദിവസത്തേക്കുള്ള മരുന്ന് വേണമെന്നും '
            'തിരഞ്ഞെടുക്കുക.',
      ),
      OrderStep(
        'ഫാർമസിസ്റ്റ് പരിശോധിക്കുന്നു',
        'കുറിപ്പടി വായിച്ച ശേഷം മരുന്നുകൾ സ്ഥിരീകരിക്കാൻ ഞങ്ങൾ വിളിക്കും.',
      ),
      OrderStep(
        'സ്ഥിരീകരിച്ച് പണമടയ്ക്കുക',
        'വാലറ്റിൽ നിന്നോ ഓൺലൈനായോ, അല്ലെങ്കിൽ സാധനം കിട്ടുമ്പോൾ '
            'പണമായോ അടയ്ക്കാം.',
      ),
      OrderStep(
        'വീട്ടിലെത്തിക്കും, അല്ലെങ്കിൽ വാങ്ങാം',
        'നിങ്ങളുടെ വിലാസത്തിൽ എത്തിക്കും, അല്ലെങ്കിൽ SHIELD സ്റ്റോറിൽ '
            'സൂക്ഷിച്ചുവയ്ക്കും.',
      ),
    ],
    pharmacistTitle: 'ഫാർമസിസ്റ്റ് കോൾ',
    pharmacistDetail:
        'നിങ്ങളുടെ കുറിപ്പടിയിലെ മരുന്നുകൾ സ്ഥിരീകരിക്കാൻ ഞങ്ങളുടെ '
        'ഫാർമസിസ്റ്റ് വിളിക്കും',
    free: 'സൗജന്യം',
    proceed: 'തുടരുക',
    remove: 'നീക്കം ചെയ്യുക',
    viewFile: 'കാണുക',
    recurringHeading: 'ആവർത്തിച്ചുള്ള ഓർഡർ',
    recurringIntro:
        'എല്ലാ മാസവും കഴിക്കുന്ന മരുന്നിനുവേണ്ടി. അവസാന തീയതി വരെ, '
        'അല്ലെങ്കിൽ നിങ്ങൾ നിർത്തുന്നതുവരെ ഞങ്ങൾ വീണ്ടും ഓർഡർ ചെയ്യും.',
    recurringToggle: 'ഈ കുറിപ്പടി ആവർത്തിക്കുക',
    fromDate: 'ആരംഭ തീയതി',
    dueDate: 'അവസാന തീയതി',
    neverExpires: 'കാലാവധി ഇല്ല',
    selectDate: 'തീയതി തിരഞ്ഞെടുക്കുക',
    dueBeforeFrom: 'അവസാന തീയതി ആരംഭ തീയതിക്ക് ശേഷമായിരിക്കണം.',
    yourPrescriptions: 'നിങ്ങളുടെ കുറിപ്പടികൾ',
    yourPrescriptionsIntro:
        'ഓർഡർ നൽകുക; ഫാർമസിസ്റ്റ് കുറിപ്പടി വായിച്ച്, നിങ്ങളെ വിളിച്ച്, '
        'മരുന്നുകളുടെ പട്ടിക ഈ കാർഡിലേക്ക് അയയ്ക്കും.',
    newPrescription: 'പുതിയ കുറിപ്പടി',
    addPrescription: 'കുറിപ്പടി ചേർക്കുക',
    addNewPrescription: 'പുതിയ കുറിപ്പടി ചേർക്കുക',
    deliveryDetails: 'ഡെലിവറി വിവരങ്ങൾ',
    deliveryDetailsIntro:
        'കോളിൽ ഓർഡർ സ്ഥിരീകരിച്ച ശേഷം ഫാർമസിസ്റ്റ് അത് അയയ്ക്കുന്ന വിലാസം.',
    noDeliveryAddress: 'ഇതുവരെ ഡെലിവറി വിലാസം ഇല്ല',
    addDeliveryAddress: 'ഡെലിവറി വിലാസം ചേർക്കുക',
    changeAddress: 'മാറ്റുക',
    patientRow: 'രോഗി',
    doctorRow: 'ഡോക്ടർ',
    doctorHint: 'ഡോക്ടറുടെ പേര്',
    repeatsRow: 'ആവർത്തനം',
    product: 'മരുന്ന്',
    intake: 'അളവ്',
    total: 'ആകെ',
    intakeHelp:
        'മൂന്ന് അക്കങ്ങൾ — രാവിലെ, ഉച്ചയ്ക്ക്, രാത്രി. 101 എന്നാൽ രാവിലെ '
        'ഒന്നും രാത്രി ഒന്നും; 110 എന്നാൽ രാവിലെയും ഉച്ചയ്ക്കും; 001 '
        'എന്നാൽ രാത്രി മാത്രം.',
    awaitingReview: 'ഞങ്ങളുടെ ഫാർമസിസ്റ്റ് ഈ കുറിപ്പടി വായിക്കുന്നു',
    awaitingReviewDetail:
        'കൗണ്ടറിൽ പരിശോധിച്ചതിനുശേഷം മരുന്നുകളും അളവും ഇവിടെ കാണാം; '
        'സാധാരണയായി കുറച്ചു മിനിറ്റുകൾക്കുള്ളിൽ.',
    intakeSlots: ['രാവിലെ', 'ഉച്ചയ്ക്ക്', 'രാത്രി'],
    intakeNotSet: 'നൽകിയിട്ടില്ല',
    units: 'എണ്ണം',
    addToCart: 'കാർട്ടിൽ ചേർക്കുക',
    inCart: 'കാർട്ടിലുണ്ട്',
    delete: 'ഇല്ലാതാക്കുക',
    prescriptionRemoved: 'കുറിപ്പടി നീക്കി',
    undo: 'തിരികെ',
    sentToCart: 'കാർട്ടിലേക്ക് അയച്ചു',
    proceedToDelivery: 'ഡെലിവറിയിലേക്ക് തുടരുക',
    beforeOrderNote:
        'താഴെ ഓർഡർ നൽകുക. ശേഷം ഫാർമസിസ്റ്റ് കുറിപ്പടി വായിച്ച് '
        'മരുന്നുകളുടെ പട്ടിക തയ്യാറാക്കും.',
    orderPlacedTitle: 'ഓർഡർ നൽകി',
    orderPlacedDetail:
        'മരുന്നുകളും വിലയും സ്ഥിരീകരിക്കാൻ ഫാർമസിസ്റ്റ് നിങ്ങളെ വിളിക്കും. '
        'അവർ വിവരങ്ങൾ അയയ്ക്കുമ്പോൾ ഈ കാർഡ് പൂർത്തിയാകും.',
    intakeCardReady: 'അളവ് കാർഡ് തയ്യാറായി',
    viewMedicines: 'മരുന്നുകൾ കാണുക',
    hideMedicines: 'മറയ്ക്കുക',
    medicineSingular: 'മരുന്ന്',
    medicinePlural: 'മരുന്നുകൾ',
  );
}
