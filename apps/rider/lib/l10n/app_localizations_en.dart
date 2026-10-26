// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Aavagaman';

  @override
  String get appTagline => 'Safar • Aapke Saath';

  @override
  String get splashQuote => 'Har safar ka apna ek maqsad hota hai.';

  @override
  String get homeWhereTo => 'Where to?';

  @override
  String get homeCurrentLocation => 'Current location';

  @override
  String get homeLocationDenied =>
      'Location is off, so the map shows Connaught Place. Allow location to book from where you are.';

  @override
  String get homeLocationUnavailable =>
      'Couldn\'t find you yet, so the map shows Connaught Place. Step outside or near a window and retry.';

  @override
  String get homeOpenSettings => 'Open settings';

  @override
  String get homeAllowLocation => 'Allow location';

  @override
  String homeNearbyCars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cars nearby',
      one: '1 car nearby',
      zero: 'No cars nearby right now',
    );
    return '$_temp0';
  }

  @override
  String get searchTitle => 'Set drop location';

  @override
  String get searchHint => 'Search for a place or address';

  @override
  String get searchMinChars => 'Type at least 3 characters';

  @override
  String get searchNoResults => 'No places found';

  @override
  String get searchUnavailable =>
      'Place search isn\'t set up on this build. Type the address, then set the location on the map.';

  @override
  String get searchSetOnMap => 'Set location on map';

  @override
  String get searchRecent => 'Recent';

  @override
  String searchUseTyped(String text) {
    return 'Use \"$text\" and set location on map';
  }

  @override
  String get pickTitleDrop => 'Set drop on map';

  @override
  String get pickTitlePickup => 'Set pickup on map';

  @override
  String get pickHint => 'Move the map until the pin is on the exact spot.';

  @override
  String get pickAddressLabel => 'Address or landmark';

  @override
  String get pickConfirm => 'Confirm location';

  @override
  String pickPinnedAddress(String lat, String lng) {
    return 'Pinned location ($lat, $lng)';
  }

  @override
  String get confirmTitle => 'Confirm your ride';

  @override
  String get confirmPickup => 'Pickup';

  @override
  String get confirmDrop => 'Drop';

  @override
  String get confirmChange => 'Change';

  @override
  String get confirmEstimating => 'Getting your fare…';

  @override
  String get confirmFareLabel => 'Estimated fare';

  @override
  String confirmTripMeta(String distance, String duration) {
    return '$distance · about $duration';
  }

  @override
  String get vehicleBike => 'Bike';

  @override
  String get vehicleAuto => 'Auto';

  @override
  String get vehicleMini => 'Mini';

  @override
  String get vehicleSedan => 'Sedan';

  @override
  String vehicleSeats(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'up to $count seats',
      one: '1 seat',
    );
    return '$_temp0';
  }

  @override
  String get confirmPayment => 'Payment';

  @override
  String get confirmPayCash => 'Cash';

  @override
  String get confirmPayOnline => 'Pay online';

  @override
  String get confirmOutOfArea =>
      'Your drop is outside our service area. The ride can be booked, but the final fare may differ from this estimate.';

  @override
  String get confirmBook => 'Book ride';

  @override
  String get confirmFareChanged =>
      'Fares were updated. Here is a fresh estimate.';

  @override
  String get findingTitle => 'Finding your driver';

  @override
  String get findingSubtitle =>
      'We\'re asking nearby drivers. This usually takes under a minute.';

  @override
  String get findingStillLooking => 'Still looking… hang on a moment.';

  @override
  String get findingCancel => 'Cancel ride';

  @override
  String get findingCancelTitle => 'Cancel this ride?';

  @override
  String get findingCancelBody => 'You can book again any time.';

  @override
  String get findingKeep => 'Keep looking';

  @override
  String get findingConfirmCancel => 'Yes, cancel';

  @override
  String get rideCancelled => 'Your ride was cancelled';

  @override
  String rideCancelledWithFee(String fee) {
    return 'Your ride was cancelled. A $fee cancellation fee will be added to your next trip.';
  }

  @override
  String get assignedOnTheWay => 'Your driver is on the way';

  @override
  String get assignedArrived => 'Your driver has arrived';

  @override
  String assignedEta(String duration) {
    return 'Arriving in $duration';
  }

  @override
  String get assignedEtaUnknown => 'Calculating arrival time…';

  @override
  String get assignedOtpLabel => 'Trip OTP';

  @override
  String get assignedOtpHint =>
      'Share this code with your driver only when you get in.';

  @override
  String get assignedCall => 'Call';

  @override
  String get assignedCallHint => 'Calling unlocks when your driver arrives';

  @override
  String get assignedCallViaHint =>
      'Calls go through Aavagaman\'s number, so your number stays private';

  @override
  String callConnecting(String number) {
    return 'Calling you from $number. Pick up to talk to your driver.';
  }

  @override
  String get callFailed => 'Couldn\'t connect the call. Please try again.';

  @override
  String get assignedShare => 'Share trip';

  @override
  String get assignedSos => 'SOS';

  @override
  String get assignedCancel => 'Cancel ride';

  @override
  String get assignedCancelTitle => 'Cancel this ride?';

  @override
  String get assignedCancelBody => 'Your driver is already on the way.';

  @override
  String get assignedCancelFeeWarning =>
      'It\'s been more than 2 minutes since your driver accepted, so a cancellation fee may apply.';

  @override
  String assignedRating(String rating) {
    return '$rating ★';
  }

  @override
  String get statusPaid => 'Payment received';

  @override
  String get statusNoDriver => 'No drivers available';

  @override
  String get statusNoDriverBody =>
      'No drivers are available right now. Please try again in a few minutes.';

  @override
  String get statusCancelledBody => 'This ride was cancelled.';

  @override
  String statusCancelledReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String statusCancellationFee(String fee) {
    return 'Cancellation fee: $fee';
  }

  @override
  String get backToHome => 'Back to home';

  @override
  String get done => 'Done';

  @override
  String shareText(String url) {
    return 'Track my ride live: $url';
  }

  @override
  String get shareSubject => 'My ride';

  @override
  String get shareUnavailable => 'Sharing isn\'t available right now.';

  @override
  String get sosTitle => 'Emergency SOS';

  @override
  String get sosBody =>
      'This will call 112 and alert our safety team with your location.';

  @override
  String get sosConfirm => 'Call 112';

  @override
  String get sosAlerted => 'Our team has been alerted';

  @override
  String get sosFailed =>
      'We couldn\'t alert our team. If you are in danger, call 112.';

  @override
  String get tripTitle => 'Trip in progress';

  @override
  String tripHeading(String drop) {
    return 'Heading to $drop';
  }

  @override
  String tripEstimate(String range) {
    return 'Estimated fare $range';
  }

  @override
  String get payTitle => 'Trip completed';

  @override
  String payTripStats(String distance, String duration) {
    return '$distance · $duration';
  }

  @override
  String get payFare => 'Trip fare';

  @override
  String payFareInclGst(String gst) {
    return 'Includes $gst GST';
  }

  @override
  String get payCancellationFee => 'Cancellation fee (earlier ride)';

  @override
  String get payTotal => 'Total';

  @override
  String payCashInstruction(String amount) {
    return 'Pay $amount cash to your driver';
  }

  @override
  String get payCashWaiting => 'Waiting for your driver to confirm…';

  @override
  String get payCashAfterOnlineNote =>
      'Because an online payment was started, your driver can confirm cash after a few minutes.';

  @override
  String payOnlineButton(String amount) {
    return 'Pay $amount online';
  }

  @override
  String get payOnlineOpening => 'Opening payment…';

  @override
  String get payOnlineVerifying => 'Confirming your payment…';

  @override
  String payDescription(String drop) {
    return 'Ride to $drop';
  }

  @override
  String get payFailedBody => 'The payment didn\'t go through.';

  @override
  String get payCancelled => 'You cancelled the payment.';

  @override
  String get payVerifyFailed =>
      'We couldn\'t confirm the payment yet. If money was deducted it will be confirmed automatically within a few minutes.';

  @override
  String get payRetry => 'Try again';

  @override
  String get paySwitchToCash => 'Pay cash to the driver instead';

  @override
  String get payUnavailable =>
      'Online payment isn\'t available right now. Please pay cash.';

  @override
  String get payReceiptFailed => 'Couldn\'t load the fare breakdown.';

  @override
  String get rateTitle => 'How was your trip?';

  @override
  String rateSubtitle(String driver) {
    return 'Rate your ride with $driver';
  }

  @override
  String ratePaidAmount(String amount) {
    return '$amount paid. Thanks for riding with us.';
  }

  @override
  String get rateCommentLabel => 'Add a comment (optional)';

  @override
  String get rateSubmit => 'Submit rating';

  @override
  String get rateSkip => 'Skip';

  @override
  String get rateThanks => 'Thanks for your feedback';

  @override
  String rateStars(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n stars',
      one: '1 star',
    );
    return '$_temp0';
  }

  @override
  String get menuHistory => 'Ride history';

  @override
  String get historyTitle => 'Ride history';

  @override
  String get historyEmpty => 'No rides yet. Your trips will appear here.';

  @override
  String get historyLoadMore => 'Load more';

  @override
  String get historyLoadFailed => 'Couldn\'t load your rides.';

  @override
  String get detailTitle => 'Ride details';

  @override
  String get detailTimeline => 'Timeline';

  @override
  String get detailReceipt => 'Receipt';

  @override
  String detailCancelledBy(String actor) {
    return 'Cancelled by $actor';
  }

  @override
  String get detailFeeCarriedNote => 'Added to your next completed ride.';

  @override
  String detailPaidWith(String method) {
    return 'Paid · $method';
  }

  @override
  String detailPaymentPending(String method) {
    return 'Payment pending · $method';
  }

  @override
  String get detailRate => 'Rate this ride';

  @override
  String get detailAlreadyRated => 'You\'ve already rated this ride.';

  @override
  String get statusLabelRequested => 'Requested';

  @override
  String get statusLabelAccepted => 'Driver assigned';

  @override
  String get statusLabelArrived => 'Driver arrived';

  @override
  String get statusLabelStarted => 'Trip started';

  @override
  String get statusLabelCompleted => 'Completed';

  @override
  String get statusLabelPaid => 'Paid';

  @override
  String get statusLabelCancelled => 'Cancelled';

  @override
  String get statusLabelNoDriver => 'No driver found';

  @override
  String get actorRider => 'you';

  @override
  String get actorDriver => 'the driver';

  @override
  String get actorAdmin => 'support';

  @override
  String get actorSystem => 'the system';

  @override
  String get paymentCash => 'Cash';

  @override
  String get paymentOnline => 'Online';

  @override
  String get paidWithUpi => 'UPI';

  @override
  String get paidWithCard => 'Card';

  @override
  String get paidWithWallet => 'Wallet';

  @override
  String get rideLoadFailed => 'Couldn\'t load your ride.';

  @override
  String get reconnecting => 'Reconnecting…';

  @override
  String get phoneTitle => 'Enter your mobile number';

  @override
  String get phoneSubtitle => 'We\'ll send you a 6-digit code to log in.';

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
  String get nameTitle => 'What\'s your name?';

  @override
  String get nameSubtitle => 'Your driver will see this name.';

  @override
  String get nameLabel => 'Full name';

  @override
  String get nameRequired => 'Enter your name';

  @override
  String homeGreeting(String name) {
    return 'Hi $name';
  }

  @override
  String get menuProfile => 'Profile';

  @override
  String get menuHelp => 'Help & support';

  @override
  String get menuPrivacy => 'Privacy policy';

  @override
  String get menuLogout => 'Log out';

  @override
  String get menuDeleteAccount => 'Delete account';

  @override
  String get profileTitle => 'Profile';

  @override
  String get emailLabel => 'Email (optional)';

  @override
  String get invalidEmail => 'Enter a valid email address';

  @override
  String get phoneReadOnly => 'Mobile number';

  @override
  String get save => 'Save';

  @override
  String get profileSaved => 'Profile updated';

  @override
  String get helpTitle => 'Help & support';

  @override
  String get helpIntro => 'Need help with a ride or your account? Contact us:';

  @override
  String get helpPhoneLabel => 'Phone';

  @override
  String get helpPhone => '+91 00000 00000';

  @override
  String get helpEmailLabel => 'Email';

  @override
  String get helpEmail => 'support@example.com';

  @override
  String get helpHours => 'Support hours: 8 am – 10 pm IST, every day.';

  @override
  String get privacyTitle => 'Privacy policy';

  @override
  String get privacyBody =>
      'This is a placeholder privacy policy. The final policy will explain what we collect (your mobile number, name, optional email, ride locations and payment records), why we collect it (to arrange and bill rides, keep riders and drivers safe, and meet legal requirements), how long we keep it, and how to ask for a copy or deletion of your data.\n\nYou can delete your account at any time from the menu. Your personal details are then removed; ride records are kept in anonymised form for accounting.';

  @override
  String get logoutConfirmTitle => 'Log out?';

  @override
  String get logoutConfirmBody => 'You\'ll need a new code to log in again.';

  @override
  String get deleteConfirmTitle => 'Delete your account?';

  @override
  String get deleteConfirmBody =>
      'Your name, number and email will be removed and you will be logged out. Past rides are kept in anonymised form for accounting. This cannot be undone.';

  @override
  String get deleteConfirmAction => 'Delete';

  @override
  String get cancel => 'Cancel';
}
