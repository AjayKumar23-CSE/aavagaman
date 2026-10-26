import Card, { Field } from '../../components/Card';
import type { DriverDetail } from '../../lib/drivers';
import { toast } from '../../lib/toast';
import { ExpiryValue } from './ExpiryValue';

/**
 * Parivahan's "Know Your Driving Licence Status" page (licence number + date
 * of birth + captcha). It cannot be queried automatically, so the admin
 * opens it with the values ready to paste (D-050).
 */
const PARIVAHAN_DL_STATUS_URL = 'https://parivahan.gov.in/rcdlstatus/?pur_cd=101';

/** 1990-06-15 → 15-06-1990, the order Parivahan's form uses. */
const toDdMmYyyy = (ymd: string) => ymd.split('-').reverse().join('-');

async function copy(text: string, what: string) {
  try {
    await navigator.clipboard.writeText(text);
    toast.success(`${what} copied`);
  } catch {
    toast.error(`Couldn't copy the ${what.toLowerCase()}; select it and copy by hand`);
  }
}

function CopyButton({ text, what }: { text: string; what: string }) {
  return (
    <button
      type="button"
      onClick={() => copy(text, what)}
      className="ml-2 rounded border border-gray-300 px-2 py-0.5 text-xs text-gray-700 hover:bg-gray-50"
    >
      Copy
    </button>
  );
}

/** Licence number, date of birth, the offline format check and the Parivahan lookup. */
export default function LicenceCheck({ driver }: { driver: DriverDetail }) {
  const check = driver.licence_check;
  const dob = driver.date_of_birth ? toDdMmYyyy(driver.date_of_birth) : null;

  const openParivahan = () => {
    if (driver.licence_no) void copy(driver.licence_no, 'Licence number');
    window.open(PARIVAHAN_DL_STATUS_URL, '_blank', 'noopener');
  };

  return (
    <Card
      title="Licence check"
      action={
        <button
          type="button"
          onClick={openParivahan}
          disabled={!driver.licence_no}
          className="rounded-md border border-gray-300 px-3 py-1 text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50"
        >
          Check on Parivahan ↗
        </button>
      }
    >
      <dl className="grid grid-cols-2 gap-x-4 gap-y-3">
        <Field label="Licence no.">
          {driver.licence_no && (
            <>
              <span className="font-mono">{driver.licence_no}</span>
              <CopyButton text={driver.licence_no} what="Licence number" />
            </>
          )}
        </Field>
        <Field label="Date of birth">
          {dob ? (
            <>
              <span className="font-mono">{dob}</span>
              <CopyButton text={dob} what="Date of birth" />
            </>
          ) : (
            driver.licence_no && <span className="text-gray-500">Not provided (registered before it was asked)</span>
          )}
        </Field>
        <Field label="Licence expiry">
          <ExpiryValue value={driver.licence_expiry} />
        </Field>
        <Field label="Issued by">
          {check?.standard &&
            `${check.state ? `${check.state} (${check.state_code})` : check.state_code}, RTO ${check.rto_code}, ${check.issue_year}`}
        </Field>
      </dl>

      {check &&
        (check.warnings.length ? (
          <div role="alert" className="mt-4 rounded-md border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-900">
            <p className="font-medium">The licence number needs a closer look</p>
            <ul className="mt-1 list-disc pl-5">
              {check.warnings.map((w) => (
                <li key={w}>{w}</li>
              ))}
            </ul>
          </div>
        ) : (
          <p className="mt-4 text-sm text-green-700">The number is in the standard format.</p>
        ))}

      <p className="mt-3 text-xs text-gray-500">
        The format check cannot tell whether the licence exists. Open Parivahan (the licence number is copied for you),
        paste it, enter the date of birth and the captcha, then check that the name matches, the status is active and
        the validity matches the uploaded licence.
      </p>
    </Card>
  );
}
