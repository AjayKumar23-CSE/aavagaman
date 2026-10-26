// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Aavagaman Driver';

  @override
  String get appTagline => 'Safar • Aapke Saath';

  @override
  String get splashQuote => 'Har safar ka apna ek maqsad hota hai.';

  @override
  String get homeStatusOffline => 'You\'re offline';

  @override
  String get homeStatusGoingOnline => 'Going online…';

  @override
  String get homeStatusOnline => 'You\'re online';

  @override
  String get homeStatusReconnecting => 'Reconnecting…';

  @override
  String get homeStatusGoingOffline => 'Going offline…';

  @override
  String get homeOfflineHint => 'Switch on to start receiving ride requests.';

  @override
  String get homeOnlineHint =>
      'Stay on this screen or lock your phone — requests will ring.';

  @override
  String get homeReconnectingHint =>
      'Connection lost. We\'ll put you back online automatically.';

  @override
  String get homeOnTripHint =>
      'You\'re on a trip. Finish it before going offline.';

  @override
  String get homeSwitchLabel => 'Online';

  @override
  String get homeViewTrip => 'View current trip';

  @override
  String get homeTodayEarnings => 'Today\'s earnings';

  @override
  String get homeEarningsNote => 'After commission and GST';

  @override
  String get homeLocationDenied => 'Allow location access to go online.';

  @override
  String get homeBackgroundLocationDenied =>
      'Allow location access \"All the time\" so ride requests reach you while the screen is off.';

  @override
  String get homeNotificationsDenied =>
      'Allow notifications so you hear ride requests.';

  @override
  String get homeLocationServiceOff =>
      'Turn on location services to go online.';

  @override
  String get homeNoFix =>
      'Couldn\'t get your location. Move to an open area and try again.';

  @override
  String get homeOpenSettings => 'Open settings';

  @override
  String get homeBatteryMenu => 'Battery settings';

  @override
  String get homeLocate => 'My location';

  @override
  String get onlineNotificationTitle => 'You are online';

  @override
  String get onlineNotificationBody => 'Receiving ride requests nearby';

  @override
  String get channelRidesName => 'Ride requests';

  @override
  String get channelRidesDescription => 'New ride requests (rings loudly)';

  @override
  String get channelPresenceName => 'Online status';

  @override
  String get channelPresenceDescription => 'Shown while you are online';

  @override
  String get offerTitle => 'New ride request';

  @override
  String offersTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ride requests',
      one: 'New ride request',
    );
    return '$_temp0';
  }

  @override
  String get offerPickup => 'Pickup';

  @override
  String get offerDrop => 'Drop';

  @override
  String offerDistance(String distance) {
    return '$distance to pickup';
  }

  @override
  String offerFare(String range) {
    return 'Fare $range';
  }

  @override
  String get offerAccept => 'Accept';

  @override
  String get offerReject => 'Reject';

  @override
  String get offerExpired => 'This request has expired';

  @override
  String get offerAccepting => 'Accepting…';

  @override
  String offerNotificationBody(String pickup) {
    return '$pickup · tap to view';
  }

  @override
  String get tripTitle => 'Navigate to pickup';

  @override
  String get tripRider => 'Rider';

  @override
  String get tripPickup => 'Pickup';

  @override
  String get tripDrop => 'Drop';

  @override
  String get tripNavigate => 'Navigate';

  @override
  String get tripCall => 'Call';

  @override
  String get tripCallHint => 'Calling unlocks when you arrive';

  @override
  String get tripCallVia => 'Call via Aavagaman';

  @override
  String get tripNumberPrivate => 'Number private · calls go via Aavagaman';

  @override
  String callConnecting(String number) {
    return 'Calling you from $number. Pick up to talk to the rider.';
  }

  @override
  String get callFailed => 'Couldn\'t connect the call. Please try again.';

  @override
  String get tripArrived => 'Arrived';

  @override
  String get tripStart => 'Start trip';

  @override
  String get tripEnd => 'End trip';

  @override
  String get tripStatusAccepted => 'Head to the pickup';

  @override
  String get tripStatusArrived =>
      'You\'re at the pickup — waiting for the rider';

  @override
  String get tripStatusStarted => 'Trip in progress';

  @override
  String get tripStatusCompleted => 'Trip completed — collect the fare';

  @override
  String tripFare(String range) {
    return 'Fare $range';
  }

  @override
  String get tripReassigned => 'This ride was reassigned to another driver.';

  @override
  String get tripCancelledByRider => 'The rider cancelled this ride.';

  @override
  String get tripEnded => 'This ride has ended.';

  @override
  String get backToHome => 'Back to home';

  @override
  String get tripNavigateFailed => 'Couldn\'t open a navigation app.';

  @override
  String get tripTitleOnTrip => 'On trip';

  @override
  String get tripTitlePayment => 'Collect payment';

  @override
  String get tripTitleRate => 'Rate the rider';

  @override
  String get tripStepPickup => 'Pickup';

  @override
  String get tripStepTrip => 'Trip';

  @override
  String get tripStepPayment => 'Payment';

  @override
  String get tripNavigateToDrop => 'Navigate to drop';

  @override
  String get tripOtpLabel => 'Rider\'s 4-digit OTP';

  @override
  String get tripOtpHint => 'Ask the rider for the code shown in their app.';

  @override
  String get tripEndConfirmTitle => 'End the trip?';

  @override
  String get tripEndConfirmBody =>
      'End the trip only when the rider has reached the drop.';

  @override
  String get tripCancel => 'Cancel ride';

  @override
  String get tripLocationUnavailable =>
      'Couldn\'t get your location. Check that GPS is on and try again.';

  @override
  String get tripYouCancelled =>
      'You cancelled this ride. It has gone back to other drivers.';

  @override
  String get tripNoShowCancelled =>
      'Ride cancelled as a rider no-show. The rider will be charged the cancellation fee.';

  @override
  String get cancelTitle => 'Why are you cancelling?';

  @override
  String get cancelWarning =>
      'Cancellations count against you: three in a day pauses your account.';

  @override
  String get cancelReasonVehicleBreakdown => 'Vehicle breakdown';

  @override
  String get cancelReasonRiderNotReachable => 'Rider not reachable';

  @override
  String get cancelReasonRiderNoShow => 'Rider didn\'t show up';

  @override
  String get cancelReasonWrongPickup => 'Wrong pickup location';

  @override
  String get cancelReasonOther => 'Other';

  @override
  String cancelNoShowWait(int minutes) {
    return 'Available after waiting $minutes min at the pickup';
  }

  @override
  String get cancelOtherHint => 'Tell us what happened';

  @override
  String get cancelConfirm => 'Cancel ride';

  @override
  String get cancelKeep => 'Keep ride';

  @override
  String get paymentAmountDue => 'Amount to collect';

  @override
  String get paymentFare => 'Trip fare';

  @override
  String get paymentPreviousFee => 'Earlier cancellation fee';

  @override
  String paymentTrip(String distance, String duration) {
    return '$distance · $duration';
  }

  @override
  String get paymentMethodCash => 'Rider pays cash';

  @override
  String get paymentMethodOnline => 'Rider pays online';

  @override
  String get paymentCashCollected => 'Cash collected';

  @override
  String get paymentCashConfirmTitle => 'Cash collected?';

  @override
  String paymentCashConfirmBody(String amount) {
    return 'Confirm you received $amount in cash from the rider.';
  }

  @override
  String get paymentWaitingOnline => 'Waiting for the rider\'s online payment…';

  @override
  String get paymentOnlineFallback =>
      'If the rider pays you in cash instead, tap Cash collected once you have it.';

  @override
  String get paymentReceived => 'Payment received';

  @override
  String get rateTitle => 'How was the rider?';

  @override
  String get rateSubmit => 'Submit';

  @override
  String get rateSkip => 'Skip';

  @override
  String get rateFailed => 'Couldn\'t send your rating.';

  @override
  String get sosTooltip => 'SOS';

  @override
  String get sosTitle => 'Emergency?';

  @override
  String get sosBody =>
      'This calls 112 and alerts our support team with your location.';

  @override
  String get sosConfirm => 'Call 112';

  @override
  String get sosAlerted => 'Our support team has been alerted.';

  @override
  String get sosFailed =>
      'Couldn\'t alert the support team. Call 112 if you haven\'t already.';

  @override
  String get menuEarnings => 'Earnings';

  @override
  String get menuHistory => 'Trip history';

  @override
  String get earningsTitle => 'Earnings';

  @override
  String get earningsToday => 'Today';

  @override
  String get earningsWeek => 'This week';

  @override
  String earningsTrips(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trips',
      one: '1 trip',
    );
    return '$_temp0';
  }

  @override
  String get earningsNet => 'You earn';

  @override
  String get earningsGross => 'Fares';

  @override
  String get earningsCommission => 'Commission';

  @override
  String get earningsGst => 'GST';

  @override
  String get earningsCash => 'Cash collected';

  @override
  String get earningsOnline => 'Paid online';

  @override
  String get earningsRecent => 'Recent trips';

  @override
  String get earningsSettlementNote =>
      'Settlements are prepared every Monday for the previous week (Monday–Sunday).';

  @override
  String earningsTripLine(String fare, String commission, String gst) {
    return 'Fare $fare · Commission $commission · GST $gst';
  }

  @override
  String get loadFailed => 'Couldn\'t load this. Check your connection.';

  @override
  String get historyTitle => 'Trip history';

  @override
  String get historyEmpty => 'No trips yet.';

  @override
  String get historyLoadMore => 'Load more';

  @override
  String get historyStatusPaid => 'Paid';

  @override
  String get historyStatusCompleted => 'Awaiting payment';

  @override
  String get historyStatusCancelled => 'Cancelled';

  @override
  String get historyStatusActive => 'In progress';

  @override
  String get historyCancelledByYou => 'Cancelled by you';

  @override
  String get historyCancelledByRider => 'Cancelled by the rider';

  @override
  String get historyCancelledByAdmin => 'Cancelled by support';

  @override
  String get batteryTitle => 'Keep ride requests coming';

  @override
  String get batteryIntro =>
      'Android may put this app to sleep while your screen is off, so ride requests stop arriving. Turn off battery optimisation for Ride Driver once.';

  @override
  String get batteryGenericSteps =>
      'Open the battery settings for Ride Driver and choose \"Don\'t optimise\" or \"Unrestricted\".';

  @override
  String batteryBrandNote(String brand) {
    return 'On your $brand phone:';
  }

  @override
  String get batteryXiaomi =>
      'Settings → Apps → Manage apps → Ride Driver → Battery saver: No restrictions. Also enable Autostart, and lock the app in Recents (pull down on its card).';

  @override
  String get batteryVivo =>
      'Settings → Battery → Background power consumption management → Ride Driver: Allow. Also enable Autostart under i Manager → App manager.';

  @override
  String get batteryOppo =>
      'Settings → Battery → More settings → Optimise battery use → Ride Driver: Don\'t optimise. Enable \"Allow auto startup\" under App management.';

  @override
  String get batteryRealme =>
      'Settings → Battery → App battery management → Ride Driver: Allow background activity. Enable auto startup under App management.';

  @override
  String get batterySamsung =>
      'Settings → Apps → Ride Driver → Battery: Unrestricted. In Settings → Battery → Background usage limits, make sure Ride Driver is not in \"Sleeping apps\".';

  @override
  String get batteryOpenSettings => 'Open battery settings';

  @override
  String get batteryOpenAppSettings => 'Open app settings';

  @override
  String get batteryDone => 'Done';

  @override
  String get batteryLater => 'Later';

  @override
  String get phoneTitle => 'Enter your mobile number';

  @override
  String get phoneSubtitle =>
      'We\'ll send you a 6-digit code to log in or sign up as a driver.';

  @override
  String get phoneConsent =>
      'We\'ll text you a one-time code. Standard SMS charges may apply.';

  @override
  String get phoneLabel => 'Mobile number';

  @override
  String get invalidPhone => 'Enter a valid 10-digit Indian mobile number';

  @override
  String get continueLabel => 'Continue';

  @override
  String get otpTitle => 'Enter the code';

  @override
  String otpSubtitle(String phone) {
    return 'Sent by SMS to $phone';
  }

  @override
  String resendIn(String time) {
    return 'Resend code in $time';
  }

  @override
  String get resend => 'Resend code';

  @override
  String get codeResent => 'A new code is on its way';

  @override
  String get changeNumber => 'Change number';

  @override
  String get retry => 'Retry';

  @override
  String get networkError =>
      'Can\'t reach the server. Check your connection and try again.';

  @override
  String get genericError => 'Something went wrong. Please try again.';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String homeGreeting(String name) {
    return 'Hi $name';
  }

  @override
  String get homeDocsAttention =>
      'Some documents need attention before you can go online.';

  @override
  String get homeDocsAction => 'View documents';

  @override
  String get registerTitle => 'Your details';

  @override
  String get registerIntro =>
      'Tell us about you and your car. You\'ll upload documents next.';

  @override
  String get registerRejected =>
      'Your application was not approved. Please correct your details and submit again.';

  @override
  String reviewerNoteLabel(String note) {
    return 'Note from our team: $note';
  }

  @override
  String get sectionDriver => 'Driver';

  @override
  String get sectionVehicle => 'Vehicle';

  @override
  String get vehicleTypeLabel => 'Vehicle type';

  @override
  String get vehicleBike => 'Bike';

  @override
  String get vehicleAuto => 'Auto';

  @override
  String get vehicleMini => 'Mini';

  @override
  String get vehicleSedan => 'Sedan';

  @override
  String get nameLabel => 'Full name (as on licence)';

  @override
  String get licenceNoLabel => 'Driving licence number';

  @override
  String get licenceExpiryLabel => 'Licence valid until';

  @override
  String get dateOfBirthLabel => 'Date of birth (as on your licence)';

  @override
  String get dateOfBirthTooYoung =>
      'You must be at least 18 years old to drive';

  @override
  String get regNumberLabel => 'Registration number';

  @override
  String get regNumberHint => 'DL01AB1234';

  @override
  String get makeLabel => 'Make';

  @override
  String get makeHint => 'Maruti Suzuki';

  @override
  String get modelLabel => 'Model';

  @override
  String get modelHint => 'Dzire';

  @override
  String get colourLabel => 'Colour';

  @override
  String get fuelLabel => 'Fuel type';

  @override
  String get fuelPetrol => 'Petrol';

  @override
  String get fuelDiesel => 'Diesel';

  @override
  String get fuelCng => 'CNG';

  @override
  String get fuelEv => 'Electric';

  @override
  String get fieldRequired => 'Required';

  @override
  String get invalidLicenceNo => '8–20 letters and digits';

  @override
  String get invalidRegNumber => 'Looks like DL01AB1234';

  @override
  String get dateExpired => 'This date has already passed';

  @override
  String get selectDate => 'Select date';

  @override
  String get submit => 'Submit';

  @override
  String get documentsTitle => 'Documents';

  @override
  String get documentsIntro =>
      'Upload a clear photo of each document. We\'ll review them within 1–2 working days.';

  @override
  String get docDrivingLicence => 'Driving licence';

  @override
  String get docRc => 'Registration certificate (RC)';

  @override
  String get docInsurance => 'Vehicle insurance';

  @override
  String get docPermit => 'Permit';

  @override
  String get docIdProof => 'ID proof (Aadhaar, PAN or voter ID)';

  @override
  String get docSelfie => 'Selfie';

  @override
  String get docFitness => 'Fitness certificate';

  @override
  String get docOptional => 'Optional';

  @override
  String get docStatusNotUploaded => 'Not uploaded';

  @override
  String get docStatusPending => 'Under review';

  @override
  String get docStatusApproved => 'Approved';

  @override
  String get docStatusRejected => 'Rejected';

  @override
  String get docStatusExpired => 'Expired';

  @override
  String docExpires(String date) {
    return 'Valid until $date';
  }

  @override
  String get docUpload => 'Upload';

  @override
  String get docReupload => 'Re-upload';

  @override
  String get documentsContinue => 'Continue';

  @override
  String documentsRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documents left to upload',
      one: '1 document left to upload',
    );
    return '$_temp0';
  }

  @override
  String uploadTitle(String doc) {
    return 'Upload $doc';
  }

  @override
  String get uploadHintSelfie =>
      'Take a clear photo of your face in good light. No sunglasses or cap.';

  @override
  String get uploadHintDocument =>
      'Place the document on a flat surface. All four corners and the text must be readable.';

  @override
  String get uploadCamera => 'Camera';

  @override
  String get uploadGallery => 'Gallery';

  @override
  String get uploadExpiryLabel => 'Valid until';

  @override
  String get uploadIdLast4Label => 'Last 4 digits of the ID number';

  @override
  String get uploadIdLast4Help => 'We only store the last 4 digits.';

  @override
  String get uploadIdLast4Invalid => 'Enter exactly 4 digits';

  @override
  String get uploadPickFirst => 'Take or choose a photo first';

  @override
  String get uploadPreparing => 'Preparing photo…';

  @override
  String get uploadSending => 'Uploading…';

  @override
  String get uploadButton => 'Upload';

  @override
  String get uploadRetry => 'Retry upload';

  @override
  String get uploadDone => 'Document uploaded';

  @override
  String get uploadPhotoError => 'Couldn\'t read that photo. Try another one.';

  @override
  String get pendingTitle => 'Verification';

  @override
  String get pendingHeadline => 'Your profile is under review';

  @override
  String get pendingBody =>
      'We\'ll let you know as soon as you\'re approved. This usually takes 1–2 working days. Pull down to check again.';

  @override
  String get pendingNeedsAttention => 'Needs your attention';

  @override
  String get pendingNotUploaded => 'Not uploaded yet';

  @override
  String get pendingFixDocuments => 'Fix documents';

  @override
  String get pendingAllDocuments => 'Your documents';

  @override
  String get pendingRefreshFailed =>
      'Couldn\'t check your status. Pull down to try again.';

  @override
  String get suspendedTitle => 'Account paused';

  @override
  String get suspendedHeadline => 'Account paused, contact support';

  @override
  String get suspendedBody =>
      'You can\'t take rides right now. Please contact our support team to resolve this.';

  @override
  String get checkAgain => 'Check again';

  @override
  String get menuProfile => 'Profile, vehicle & documents';

  @override
  String get menuHelp => 'Help & support';

  @override
  String get menuPrivacy => 'Privacy policy';

  @override
  String get menuLogout => 'Log out';

  @override
  String get logoutConfirmTitle => 'Log out?';

  @override
  String get logoutConfirmBody => 'You\'ll need a new code to log in again.';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profilePhone => 'Mobile number';

  @override
  String get profileRating => 'Rating';

  @override
  String get profileStatus => 'Verification';

  @override
  String get statusPending => 'Pending review';

  @override
  String get statusApproved => 'Approved';

  @override
  String get statusRejected => 'Rejected';

  @override
  String get statusSuspended => 'Suspended';

  @override
  String get profileNoVehicle => 'No vehicle added yet';

  @override
  String get profileDocuments => 'Documents';

  @override
  String get helpTitle => 'Help & support';

  @override
  String get helpIntro =>
      'Questions about onboarding, documents or payouts? Contact driver support:';

  @override
  String get helpPhoneLabel => 'Phone';

  @override
  String get helpPhone => '+91 00000 00000';

  @override
  String get helpEmailLabel => 'Email';

  @override
  String get helpEmail => 'drivers@example.com';

  @override
  String get helpHours => 'Support hours: 8 am – 10 pm IST, every day.';

  @override
  String get privacyTitle => 'Privacy policy';

  @override
  String get privacyBody =>
      'This is a placeholder privacy policy. The final policy will explain what we collect from drivers (mobile number, name, date of birth, licence and vehicle details, document photos, the last 4 digits of your ID, trip locations and earnings), why we collect it (to verify drivers, arrange rides, keep riders and drivers safe, settle payments and meet legal requirements), how long we keep it, and how to ask for a copy or deletion of your data.\n\nDocument photos are stored privately and are only visible to our verification team.';

  @override
  String homeEarningsSummary(String amount, String trips) {
    return '$amount · $trips';
  }

  @override
  String get homeEarningsUnavailable => '—';
}
