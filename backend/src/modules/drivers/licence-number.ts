/**
 * Offline sanity check of an Indian driving licence number (D-050). It
 * catches typos and made-up numbers; it cannot tell whether the licence
 * exists — the admin confirms that on Parivahan.
 *
 * Standard (Sarathi) format, 15 characters: state code (2 letters), RTO code
 * (2 digits), year of first issue (4 digits), serial (7 digits), e.g.
 * DL04 2011 0012345. Older licences may differ, so a mismatch is a warning
 * for the admin, never a reason to refuse the registration.
 */

/** State / UT codes used on licences, including pre-rename ones still in circulation. */
export const LICENCE_STATES: Readonly<Record<string, string>> = {
  AN: 'Andaman and Nicobar Islands',
  AP: 'Andhra Pradesh',
  AR: 'Arunachal Pradesh',
  AS: 'Assam',
  BR: 'Bihar',
  CG: 'Chhattisgarh',
  CH: 'Chandigarh',
  DD: 'Dadra and Nagar Haveli and Daman and Diu',
  DN: 'Dadra and Nagar Haveli',
  DL: 'Delhi',
  GA: 'Goa',
  GJ: 'Gujarat',
  HP: 'Himachal Pradesh',
  HR: 'Haryana',
  JH: 'Jharkhand',
  JK: 'Jammu and Kashmir',
  KA: 'Karnataka',
  KL: 'Kerala',
  LA: 'Ladakh',
  LD: 'Lakshadweep',
  MH: 'Maharashtra',
  ML: 'Meghalaya',
  MN: 'Manipur',
  MP: 'Madhya Pradesh',
  MZ: 'Mizoram',
  NL: 'Nagaland',
  OD: 'Odisha',
  OR: 'Odisha',
  PB: 'Punjab',
  PY: 'Puducherry',
  RJ: 'Rajasthan',
  SK: 'Sikkim',
  TG: 'Telangana',
  TS: 'Telangana',
  TN: 'Tamil Nadu',
  TR: 'Tripura',
  UA: 'Uttarakhand',
  UK: 'Uttarakhand',
  UP: 'Uttar Pradesh',
  WB: 'West Bengal',
};

/** Youngest age at which any licence (a gearless two-wheeler one) can be issued. */
const MIN_ISSUE_AGE = 16;
const EARLIEST_ISSUE_YEAR = 1950;

const STANDARD = /^([A-Z]{2})(\d{2})(\d{4})(\d{7})$/;

export interface LicenceCheck {
  /** Matches the 15-character standard layout. */
  standard: boolean;
  state_code: string | null;
  state: string | null;
  rto_code: string | null;
  issue_year: number | null;
  /** Empty when nothing looks wrong. */
  warnings: string[];
}

export const normaliseLicenceNo = (no: string) => no.replace(/[\s\-/]/g, '').toUpperCase();

export function checkLicenceNumber(
  licenceNo: string | null,
  dateOfBirth: Date | null,
  now = new Date(),
): LicenceCheck | null {
  if (!licenceNo) return null;
  const m = STANDARD.exec(normaliseLicenceNo(licenceNo));
  if (!m) {
    return {
      standard: false,
      state_code: null,
      state: null,
      rto_code: null,
      issue_year: null,
      warnings: [
        'Not in the standard 15-character format (state, RTO, year of issue, 7 digits). Some older licences differ, so check it on Parivahan.',
      ],
    };
  }
  const [, stateCode, rto, yearText] = m;
  const year = Number(yearText);
  const warnings: string[] = [];
  const state = LICENCE_STATES[stateCode] ?? null;
  if (!state) warnings.push(`Unknown state code "${stateCode}".`);
  if (rto === '00') warnings.push('RTO code 00 does not exist.');
  if (year > now.getUTCFullYear()) warnings.push(`Year of issue ${year} is in the future.`);
  else if (year < EARLIEST_ISSUE_YEAR) warnings.push(`Year of issue ${year} looks wrong.`);
  if (dateOfBirth && year - dateOfBirth.getUTCFullYear() < MIN_ISSUE_AGE) {
    warnings.push(
      `Issued in ${year}, when the driver was under ${MIN_ISSUE_AGE} (born ${dateOfBirth.getUTCFullYear()}).`,
    );
  }
  return {
    standard: true,
    state_code: stateCode,
    state,
    rto_code: rto,
    issue_year: year,
    warnings,
  };
}
