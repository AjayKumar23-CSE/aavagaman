import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Aavagaman'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Safar • Aapke Saath'**
  String get appTagline;

  /// No description provided for @splashQuote.
  ///
  /// In en, this message translates to:
  /// **'Har safar ka apna ek maqsad hota hai.'**
  String get splashQuote;

  /// No description provided for @homeWhereTo.
  ///
  /// In en, this message translates to:
  /// **'Where to?'**
  String get homeWhereTo;

  /// No description provided for @homeCurrentLocation.
  ///
  /// In en, this message translates to:
  /// **'Current location'**
  String get homeCurrentLocation;

  /// No description provided for @homeLocationDenied.
  ///
  /// In en, this message translates to:
  /// **'Location is off, so the map shows Connaught Place. Allow location to book from where you are.'**
  String get homeLocationDenied;

  /// No description provided for @homeLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find you yet, so the map shows Connaught Place. Step outside or near a window and retry.'**
  String get homeLocationUnavailable;

  /// No description provided for @homeOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get homeOpenSettings;

  /// No description provided for @homeAllowLocation.
  ///
  /// In en, this message translates to:
  /// **'Allow location'**
  String get homeAllowLocation;

  /// No description provided for @homeNearbyCars.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No cars nearby right now} =1{1 car nearby} other{{count} cars nearby}}'**
  String homeNearbyCars(int count);

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Set drop location'**
  String get searchTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search for a place or address'**
  String get searchHint;

  /// No description provided for @searchMinChars.
  ///
  /// In en, this message translates to:
  /// **'Type at least 3 characters'**
  String get searchMinChars;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No places found'**
  String get searchNoResults;

  /// No description provided for @searchUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Place search isn\'t set up on this build. Type the address, then set the location on the map.'**
  String get searchUnavailable;

  /// No description provided for @searchSetOnMap.
  ///
  /// In en, this message translates to:
  /// **'Set location on map'**
  String get searchSetOnMap;

  /// No description provided for @searchRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get searchRecent;

  /// No description provided for @searchUseTyped.
  ///
  /// In en, this message translates to:
  /// **'Use \"{text}\" and set location on map'**
  String searchUseTyped(String text);

  /// No description provided for @pickTitleDrop.
  ///
  /// In en, this message translates to:
  /// **'Set drop on map'**
  String get pickTitleDrop;

  /// No description provided for @pickTitlePickup.
  ///
  /// In en, this message translates to:
  /// **'Set pickup on map'**
  String get pickTitlePickup;

  /// No description provided for @pickHint.
  ///
  /// In en, this message translates to:
  /// **'Move the map until the pin is on the exact spot.'**
  String get pickHint;

  /// No description provided for @pickAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Address or landmark'**
  String get pickAddressLabel;

  /// No description provided for @pickConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm location'**
  String get pickConfirm;

  /// No description provided for @pickPinnedAddress.
  ///
  /// In en, this message translates to:
  /// **'Pinned location ({lat}, {lng})'**
  String pickPinnedAddress(String lat, String lng);

  /// No description provided for @confirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm your ride'**
  String get confirmTitle;

  /// No description provided for @confirmPickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get confirmPickup;

  /// No description provided for @confirmDrop.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get confirmDrop;

  /// No description provided for @confirmChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get confirmChange;

  /// No description provided for @confirmEstimating.
  ///
  /// In en, this message translates to:
  /// **'Getting your fare…'**
  String get confirmEstimating;

  /// No description provided for @confirmFareLabel.
  ///
  /// In en, this message translates to:
  /// **'Estimated fare'**
  String get confirmFareLabel;

  /// No description provided for @confirmTripMeta.
  ///
  /// In en, this message translates to:
  /// **'{distance} · about {duration}'**
  String confirmTripMeta(String distance, String duration);

  /// No description provided for @vehicleBike.
  ///
  /// In en, this message translates to:
  /// **'Bike'**
  String get vehicleBike;

  /// No description provided for @vehicleAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get vehicleAuto;

  /// No description provided for @vehicleMini.
  ///
  /// In en, this message translates to:
  /// **'Mini'**
  String get vehicleMini;

  /// No description provided for @vehicleSedan.
  ///
  /// In en, this message translates to:
  /// **'Sedan'**
  String get vehicleSedan;

  /// No description provided for @vehicleSeats.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 seat} other{up to {count} seats}}'**
  String vehicleSeats(int count);

  /// No description provided for @confirmPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get confirmPayment;

  /// No description provided for @confirmPayCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get confirmPayCash;

  /// No description provided for @confirmPayOnline.
  ///
  /// In en, this message translates to:
  /// **'Pay online'**
  String get confirmPayOnline;

  /// No description provided for @confirmOutOfArea.
  ///
  /// In en, this message translates to:
  /// **'Your drop is outside our service area. The ride can be booked, but the final fare may differ from this estimate.'**
  String get confirmOutOfArea;

  /// No description provided for @confirmBook.
  ///
  /// In en, this message translates to:
  /// **'Book ride'**
  String get confirmBook;

  /// No description provided for @confirmFareChanged.
  ///
  /// In en, this message translates to:
  /// **'Fares were updated. Here is a fresh estimate.'**
  String get confirmFareChanged;

  /// No description provided for @findingTitle.
  ///
  /// In en, this message translates to:
  /// **'Finding your driver'**
  String get findingTitle;

  /// No description provided for @findingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'re asking nearby drivers. This usually takes under a minute.'**
  String get findingSubtitle;

  /// No description provided for @findingStillLooking.
  ///
  /// In en, this message translates to:
  /// **'Still looking… hang on a moment.'**
  String get findingStillLooking;

  /// No description provided for @findingCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel ride'**
  String get findingCancel;

  /// No description provided for @findingCancelTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this ride?'**
  String get findingCancelTitle;

  /// No description provided for @findingCancelBody.
  ///
  /// In en, this message translates to:
  /// **'You can book again any time.'**
  String get findingCancelBody;

  /// No description provided for @findingKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep looking'**
  String get findingKeep;

  /// No description provided for @findingConfirmCancel.
  ///
  /// In en, this message translates to:
  /// **'Yes, cancel'**
  String get findingConfirmCancel;

  /// No description provided for @rideCancelled.
  ///
  /// In en, this message translates to:
  /// **'Your ride was cancelled'**
  String get rideCancelled;

  /// No description provided for @rideCancelledWithFee.
  ///
  /// In en, this message translates to:
  /// **'Your ride was cancelled. A {fee} cancellation fee will be added to your next trip.'**
  String rideCancelledWithFee(String fee);

  /// No description provided for @assignedOnTheWay.
  ///
  /// In en, this message translates to:
  /// **'Your driver is on the way'**
  String get assignedOnTheWay;

  /// No description provided for @assignedArrived.
  ///
  /// In en, this message translates to:
  /// **'Your driver has arrived'**
  String get assignedArrived;

  /// No description provided for @assignedEta.
  ///
  /// In en, this message translates to:
  /// **'Arriving in {duration}'**
  String assignedEta(String duration);

  /// No description provided for @assignedEtaUnknown.
  ///
  /// In en, this message translates to:
  /// **'Calculating arrival time…'**
  String get assignedEtaUnknown;

  /// No description provided for @assignedOtpLabel.
  ///
  /// In en, this message translates to:
  /// **'Trip OTP'**
  String get assignedOtpLabel;

  /// No description provided for @assignedOtpHint.
  ///
  /// In en, this message translates to:
  /// **'Share this code with your driver only when you get in.'**
  String get assignedOtpHint;

  /// No description provided for @assignedCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get assignedCall;

  /// No description provided for @assignedCallHint.
  ///
  /// In en, this message translates to:
  /// **'Calling unlocks when your driver arrives'**
  String get assignedCallHint;

  /// No description provided for @assignedCallViaHint.
  ///
  /// In en, this message translates to:
  /// **'Calls go through Aavagaman\'s number, so your number stays private'**
  String get assignedCallViaHint;

  /// No description provided for @callConnecting.
  ///
  /// In en, this message translates to:
  /// **'Calling you from {number}. Pick up to talk to your driver.'**
  String callConnecting(String number);

  /// No description provided for @callFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect the call. Please try again.'**
  String get callFailed;

  /// No description provided for @assignedShare.
  ///
  /// In en, this message translates to:
  /// **'Share trip'**
  String get assignedShare;

  /// No description provided for @assignedSos.
  ///
  /// In en, this message translates to:
  /// **'SOS'**
  String get assignedSos;

  /// No description provided for @assignedCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel ride'**
  String get assignedCancel;

  /// No description provided for @assignedCancelTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this ride?'**
  String get assignedCancelTitle;

  /// No description provided for @assignedCancelBody.
  ///
  /// In en, this message translates to:
  /// **'Your driver is already on the way.'**
  String get assignedCancelBody;

  /// No description provided for @assignedCancelFeeWarning.
  ///
  /// In en, this message translates to:
  /// **'It\'s been more than 2 minutes since your driver accepted, so a cancellation fee may apply.'**
  String get assignedCancelFeeWarning;

  /// No description provided for @assignedRating.
  ///
  /// In en, this message translates to:
  /// **'{rating} ★'**
  String assignedRating(String rating);

  /// No description provided for @statusPaid.
  ///
  /// In en, this message translates to:
  /// **'Payment received'**
  String get statusPaid;

  /// No description provided for @statusNoDriver.
  ///
  /// In en, this message translates to:
  /// **'No drivers available'**
  String get statusNoDriver;

  /// No description provided for @statusNoDriverBody.
  ///
  /// In en, this message translates to:
  /// **'No drivers are available right now. Please try again in a few minutes.'**
  String get statusNoDriverBody;

  /// No description provided for @statusCancelledBody.
  ///
  /// In en, this message translates to:
  /// **'This ride was cancelled.'**
  String get statusCancelledBody;

  /// No description provided for @statusCancelledReason.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String statusCancelledReason(String reason);

  /// No description provided for @statusCancellationFee.
  ///
  /// In en, this message translates to:
  /// **'Cancellation fee: {fee}'**
  String statusCancellationFee(String fee);

  /// No description provided for @backToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get backToHome;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @shareText.
  ///
  /// In en, this message translates to:
  /// **'Track my ride live: {url}'**
  String shareText(String url);

  /// No description provided for @shareSubject.
  ///
  /// In en, this message translates to:
  /// **'My ride'**
  String get shareSubject;

  /// No description provided for @shareUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Sharing isn\'t available right now.'**
  String get shareUnavailable;

  /// No description provided for @sosTitle.
  ///
  /// In en, this message translates to:
  /// **'Emergency SOS'**
  String get sosTitle;

  /// No description provided for @sosBody.
  ///
  /// In en, this message translates to:
  /// **'This will call 112 and alert our safety team with your location.'**
  String get sosBody;

  /// No description provided for @sosConfirm.
  ///
  /// In en, this message translates to:
  /// **'Call 112'**
  String get sosConfirm;

  /// No description provided for @sosAlerted.
  ///
  /// In en, this message translates to:
  /// **'Our team has been alerted'**
  String get sosAlerted;

  /// No description provided for @sosFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t alert our team. If you are in danger, call 112.'**
  String get sosFailed;

  /// No description provided for @tripTitle.
  ///
  /// In en, this message translates to:
  /// **'Trip in progress'**
  String get tripTitle;

  /// No description provided for @tripHeading.
  ///
  /// In en, this message translates to:
  /// **'Heading to {drop}'**
  String tripHeading(String drop);

  /// No description provided for @tripEstimate.
  ///
  /// In en, this message translates to:
  /// **'Estimated fare {range}'**
  String tripEstimate(String range);

  /// No description provided for @payTitle.
  ///
  /// In en, this message translates to:
  /// **'Trip completed'**
  String get payTitle;

  /// No description provided for @payTripStats.
  ///
  /// In en, this message translates to:
  /// **'{distance} · {duration}'**
  String payTripStats(String distance, String duration);

  /// No description provided for @payFare.
  ///
  /// In en, this message translates to:
  /// **'Trip fare'**
  String get payFare;

  /// No description provided for @payFareInclGst.
  ///
  /// In en, this message translates to:
  /// **'Includes {gst} GST'**
  String payFareInclGst(String gst);

  /// No description provided for @payCancellationFee.
  ///
  /// In en, this message translates to:
  /// **'Cancellation fee (earlier ride)'**
  String get payCancellationFee;

  /// No description provided for @payTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get payTotal;

  /// No description provided for @payCashInstruction.
  ///
  /// In en, this message translates to:
  /// **'Pay {amount} cash to your driver'**
  String payCashInstruction(String amount);

  /// No description provided for @payCashWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your driver to confirm…'**
  String get payCashWaiting;

  /// No description provided for @payCashAfterOnlineNote.
  ///
  /// In en, this message translates to:
  /// **'Because an online payment was started, your driver can confirm cash after a few minutes.'**
  String get payCashAfterOnlineNote;

  /// No description provided for @payOnlineButton.
  ///
  /// In en, this message translates to:
  /// **'Pay {amount} online'**
  String payOnlineButton(String amount);

  /// No description provided for @payOnlineOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening payment…'**
  String get payOnlineOpening;

  /// No description provided for @payOnlineVerifying.
  ///
  /// In en, this message translates to:
  /// **'Confirming your payment…'**
  String get payOnlineVerifying;

  /// No description provided for @payDescription.
  ///
  /// In en, this message translates to:
  /// **'Ride to {drop}'**
  String payDescription(String drop);

  /// No description provided for @payFailedBody.
  ///
  /// In en, this message translates to:
  /// **'The payment didn\'t go through.'**
  String get payFailedBody;

  /// No description provided for @payCancelled.
  ///
  /// In en, this message translates to:
  /// **'You cancelled the payment.'**
  String get payCancelled;

  /// No description provided for @payVerifyFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm the payment yet. If money was deducted it will be confirmed automatically within a few minutes.'**
  String get payVerifyFailed;

  /// No description provided for @payRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get payRetry;

  /// No description provided for @paySwitchToCash.
  ///
  /// In en, this message translates to:
  /// **'Pay cash to the driver instead'**
  String get paySwitchToCash;

  /// No description provided for @payUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Online payment isn\'t available right now. Please pay cash.'**
  String get payUnavailable;

  /// No description provided for @payReceiptFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the fare breakdown.'**
  String get payReceiptFailed;

  /// No description provided for @rateTitle.
  ///
  /// In en, this message translates to:
  /// **'How was your trip?'**
  String get rateTitle;

  /// No description provided for @rateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Rate your ride with {driver}'**
  String rateSubtitle(String driver);

  /// No description provided for @ratePaidAmount.
  ///
  /// In en, this message translates to:
  /// **'{amount} paid. Thanks for riding with us.'**
  String ratePaidAmount(String amount);

  /// No description provided for @rateCommentLabel.
  ///
  /// In en, this message translates to:
  /// **'Add a comment (optional)'**
  String get rateCommentLabel;

  /// No description provided for @rateSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit rating'**
  String get rateSubmit;

  /// No description provided for @rateSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get rateSkip;

  /// No description provided for @rateThanks.
  ///
  /// In en, this message translates to:
  /// **'Thanks for your feedback'**
  String get rateThanks;

  /// No description provided for @rateStars.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 star} other{{n} stars}}'**
  String rateStars(int n);

  /// No description provided for @menuHistory.
  ///
  /// In en, this message translates to:
  /// **'Ride history'**
  String get menuHistory;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'Ride history'**
  String get historyTitle;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No rides yet. Your trips will appear here.'**
  String get historyEmpty;

  /// No description provided for @historyLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get historyLoadMore;

  /// No description provided for @historyLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your rides.'**
  String get historyLoadFailed;

  /// No description provided for @detailTitle.
  ///
  /// In en, this message translates to:
  /// **'Ride details'**
  String get detailTitle;

  /// No description provided for @detailTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get detailTimeline;

  /// No description provided for @detailReceipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get detailReceipt;

  /// No description provided for @detailCancelledBy.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by {actor}'**
  String detailCancelledBy(String actor);

  /// No description provided for @detailFeeCarriedNote.
  ///
  /// In en, this message translates to:
  /// **'Added to your next completed ride.'**
  String get detailFeeCarriedNote;

  /// No description provided for @detailPaidWith.
  ///
  /// In en, this message translates to:
  /// **'Paid · {method}'**
  String detailPaidWith(String method);

  /// No description provided for @detailPaymentPending.
  ///
  /// In en, this message translates to:
  /// **'Payment pending · {method}'**
  String detailPaymentPending(String method);

  /// No description provided for @detailRate.
  ///
  /// In en, this message translates to:
  /// **'Rate this ride'**
  String get detailRate;

  /// No description provided for @detailAlreadyRated.
  ///
  /// In en, this message translates to:
  /// **'You\'ve already rated this ride.'**
  String get detailAlreadyRated;

  /// No description provided for @statusLabelRequested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get statusLabelRequested;

  /// No description provided for @statusLabelAccepted.
  ///
  /// In en, this message translates to:
  /// **'Driver assigned'**
  String get statusLabelAccepted;

  /// No description provided for @statusLabelArrived.
  ///
  /// In en, this message translates to:
  /// **'Driver arrived'**
  String get statusLabelArrived;

  /// No description provided for @statusLabelStarted.
  ///
  /// In en, this message translates to:
  /// **'Trip started'**
  String get statusLabelStarted;

  /// No description provided for @statusLabelCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusLabelCompleted;

  /// No description provided for @statusLabelPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get statusLabelPaid;

  /// No description provided for @statusLabelCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusLabelCancelled;

  /// No description provided for @statusLabelNoDriver.
  ///
  /// In en, this message translates to:
  /// **'No driver found'**
  String get statusLabelNoDriver;

  /// No description provided for @actorRider.
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get actorRider;

  /// No description provided for @actorDriver.
  ///
  /// In en, this message translates to:
  /// **'the driver'**
  String get actorDriver;

  /// No description provided for @actorAdmin.
  ///
  /// In en, this message translates to:
  /// **'support'**
  String get actorAdmin;

  /// No description provided for @actorSystem.
  ///
  /// In en, this message translates to:
  /// **'the system'**
  String get actorSystem;

  /// No description provided for @paymentCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get paymentCash;

  /// No description provided for @paymentOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get paymentOnline;

  /// No description provided for @paidWithUpi.
  ///
  /// In en, this message translates to:
  /// **'UPI'**
  String get paidWithUpi;

  /// No description provided for @paidWithCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get paidWithCard;

  /// No description provided for @paidWithWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get paidWithWallet;

  /// No description provided for @rideLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your ride.'**
  String get rideLoadFailed;

  /// No description provided for @reconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get reconnecting;

  /// No description provided for @phoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your mobile number'**
  String get phoneTitle;

  /// No description provided for @phoneSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send you a 6-digit code to log in.'**
  String get phoneSubtitle;

  /// No description provided for @phoneConsent.
  ///
  /// In en, this message translates to:
  /// **'We\'ll text you a one-time code. Standard SMS charges may apply.'**
  String get phoneConsent;

  /// No description provided for @phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get phoneLabel;

  /// No description provided for @invalidPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 10-digit Indian mobile number'**
  String get invalidPhone;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @otpTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get otpTitle;

  /// No description provided for @otpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sent by SMS to {phone}'**
  String otpSubtitle(String phone);

  /// No description provided for @resendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend code in {time}'**
  String resendIn(String time);

  /// No description provided for @resend.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get resend;

  /// No description provided for @codeResent.
  ///
  /// In en, this message translates to:
  /// **'A new code is on its way'**
  String get codeResent;

  /// No description provided for @changeNumber.
  ///
  /// In en, this message translates to:
  /// **'Change number'**
  String get changeNumber;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. Check your connection and try again.'**
  String get networkError;

  /// No description provided for @genericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get genericError;

  /// No description provided for @nameTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s your name?'**
  String get nameTitle;

  /// No description provided for @nameSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your driver will see this name.'**
  String get nameSubtitle;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get nameLabel;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get nameRequired;

  /// No description provided for @homeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hi {name}'**
  String homeGreeting(String name);

  /// No description provided for @menuProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get menuProfile;

  /// No description provided for @menuHelp.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get menuHelp;

  /// No description provided for @menuPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get menuPrivacy;

  /// No description provided for @menuLogout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get menuLogout;

  /// No description provided for @menuDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get menuDeleteAccount;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get emailLabel;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get invalidEmail;

  /// No description provided for @phoneReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get phoneReadOnly;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get profileSaved;

  /// No description provided for @helpTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get helpTitle;

  /// No description provided for @helpIntro.
  ///
  /// In en, this message translates to:
  /// **'Need help with a ride or your account? Contact us:'**
  String get helpIntro;

  /// No description provided for @helpPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get helpPhoneLabel;

  /// No description provided for @helpPhone.
  ///
  /// In en, this message translates to:
  /// **'+91 00000 00000'**
  String get helpPhone;

  /// No description provided for @helpEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get helpEmailLabel;

  /// No description provided for @helpEmail.
  ///
  /// In en, this message translates to:
  /// **'support@example.com'**
  String get helpEmail;

  /// No description provided for @helpHours.
  ///
  /// In en, this message translates to:
  /// **'Support hours: 8 am – 10 pm IST, every day.'**
  String get helpHours;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyTitle;

  /// No description provided for @privacyBody.
  ///
  /// In en, this message translates to:
  /// **'This is a placeholder privacy policy. The final policy will explain what we collect (your mobile number, name, optional email, ride locations and payment records), why we collect it (to arrange and bill rides, keep riders and drivers safe, and meet legal requirements), how long we keep it, and how to ask for a copy or deletion of your data.\n\nYou can delete your account at any time from the menu. Your personal details are then removed; ride records are kept in anonymised form for accounting.'**
  String get privacyBody;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll need a new code to log in again.'**
  String get logoutConfirmBody;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get deleteConfirmTitle;

  /// No description provided for @deleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Your name, number and email will be removed and you will be logged out. Past rides are kept in anonymised form for accounting. This cannot be undone.'**
  String get deleteConfirmBody;

  /// No description provided for @deleteConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteConfirmAction;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
