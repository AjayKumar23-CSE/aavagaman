import { useState, type ReactNode } from 'react';
import { Link, useParams } from 'react-router';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import ReasonDialog from '../../components/ReasonDialog';
import StatusBadge from '../../components/StatusBadge';
import { errorMessage } from '../../lib/api';
import {
  DOC_LABEL,
  driverAction,
  getDriver,
  reviewDocument,
  updateVehicle,
  type DocumentHistoryItem,
  type DriverAction,
  type DriverDetail as Driver,
  type VehiclePatch,
  type VerificationStatus,
} from '../../lib/drivers';
import { formatIST } from '../../lib/time';
import { toast } from '../../lib/toast';
import DocumentsSection from './DocumentsSection';
import { ExpiryValue } from './ExpiryValue';
import LicenceCheck from './LicenceCheck';
import VehicleEditDialog from './VehicleEditDialog';

/** Signed document URLs live 5 minutes; refresh a little before that. */
const URL_REFRESH_MS = 4 * 60_000;

const ACTIONS: {
  action: DriverAction;
  label: string;
  from: VerificationStatus[];
  destructive: boolean;
  done: string;
}[] = [
  {
    action: 'approve',
    label: 'Approve driver',
    from: ['pending', 'rejected'],
    destructive: false,
    done: 'Driver approved',
  },
  { action: 'reinstate', label: 'Reinstate', from: ['suspended'], destructive: false, done: 'Driver reinstated' },
  {
    action: 'reject',
    label: 'Reject driver',
    from: ['pending', 'approved'],
    destructive: true,
    done: 'Driver rejected',
  },
  { action: 'suspend', label: 'Suspend', from: ['approved'], destructive: true, done: 'Driver suspended' },
];

type Dialog =
  | { kind: 'driver'; action: 'reject' | 'suspend' }
  | { kind: 'document'; doc: DocumentHistoryItem }
  | { kind: 'vehicle' };

function Card({ title, action, children }: { title: string; action?: ReactNode; children: ReactNode }) {
  return (
    <section className="rounded-lg border border-gray-200 bg-white p-5">
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500">{title}</h2>
        {action}
      </div>
      {children}
    </section>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <dt className="text-xs text-gray-500">{label}</dt>
      <dd className="text-sm text-gray-900">{children ?? '—'}</dd>
    </div>
  );
}

function initials(name: string | null): string {
  return (name ?? '?')
    .split(/\s+/)
    .map((p) => p[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();
}

export default function DriverDetail() {
  const { id = '' } = useParams();
  const queryClient = useQueryClient();
  const [dialog, setDialog] = useState<Dialog | null>(null);

  const query = useQuery({
    queryKey: ['driver', id],
    queryFn: () => getDriver(id),
    refetchInterval: URL_REFRESH_MS,
  });
  const driver = query.data;

  const refresh = () => void query.refetch();
  // An image failing after its link has aged is most likely an expired signature: fetch fresh links.
  // Fresh links that fail (e.g. storage unreachable) just show the placeholder, so this cannot loop.
  const onUrlError = () => {
    if (Date.now() - query.dataUpdatedAt > URL_REFRESH_MS && !query.isFetching) refresh();
  };

  const invalidateList = () => queryClient.invalidateQueries({ queryKey: ['drivers'] });

  const driverMutation = useMutation({
    mutationFn: ({ action, note }: { action: DriverAction; note?: string }) => driverAction(id, action, note),
    onSuccess: (data, { action }) => {
      queryClient.setQueryData(['driver', id], data);
      void invalidateList();
      toast.success(ACTIONS.find((a) => a.action === action)?.done ?? 'Saved');
    },
  });

  const docMutation = useMutation({
    mutationFn: ({
      doc,
      decision,
      note,
    }: {
      doc: DocumentHistoryItem;
      decision: 'approve' | 'reject';
      note?: string;
    }) => reviewDocument(id, doc.id, decision, note),
    onSuccess: (_data, { doc, decision }) => {
      void queryClient.invalidateQueries({ queryKey: ['driver', id] });
      void invalidateList();
      toast.success(`${DOC_LABEL[doc.doc_type]} ${decision === 'approve' ? 'approved' : 'rejected'}`);
    },
  });

  const vehicleMutation = useMutation({
    mutationFn: (patch: VehiclePatch) => updateVehicle(id, patch),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['driver', id] });
      void invalidateList();
      toast.success('Vehicle updated');
    },
  });

  if (query.isPending) return <p className="text-sm text-gray-500">Loading driver…</p>;

  if (query.isError || !driver) {
    return (
      <div className="space-y-4">
        <Link to="/drivers" className="text-sm text-gray-600 hover:text-gray-900">
          ← Drivers
        </Link>
        <div
          role="alert"
          className="flex items-center justify-between rounded-md bg-red-50 px-4 py-3 text-sm text-red-700"
        >
          <span>{errorMessage(query.error)}</span>
          <button type="button" onClick={refresh} className="font-medium underline">
            Retry
          </button>
        </div>
      </div>
    );
  }

  const available = ACTIONS.filter((a) => a.from.includes(driver.verification_status));
  const busyDocId = docMutation.isPending ? docMutation.variables.doc.id : null;

  function runAction(action: DriverAction) {
    if (action === 'reject' || action === 'suspend') {
      setDialog({ kind: 'driver', action });
      return;
    }
    driverMutation.mutate({ action }, { onError: (e) => toast.error(errorMessage(e)) });
  }

  return (
    <div className="space-y-6">
      <Link to="/drivers" className="text-sm text-gray-600 hover:text-gray-900">
        ← Drivers
      </Link>

      {/* Header: identity, verification status and actions */}
      <section className="rounded-lg border border-gray-200 bg-white p-5">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="flex items-center gap-4">
            <Avatar key={driver.selfie_url ?? 'none'} driver={driver} onUrlError={onUrlError} />
            <div>
              <div className="flex items-center gap-3">
                <h1 className="text-2xl font-semibold text-gray-900">{driver.name ?? 'Unnamed driver'}</h1>
                <StatusBadge status={driver.verification_status} />
              </div>
              <p className="font-mono text-sm text-gray-600">{driver.phone}</p>
              <p className="text-xs text-gray-500">
                {driver.can_go_online ? 'Eligible to go online' : 'Not eligible to go online'}
                {query.isFetching && ' · refreshing…'}
              </p>
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            {available.map((a) => (
              <button
                key={a.action}
                type="button"
                disabled={driverMutation.isPending}
                onClick={() => runAction(a.action)}
                className={
                  a.destructive
                    ? 'rounded-md border border-red-300 bg-white px-4 py-2 text-sm font-medium text-red-700 hover:bg-red-50 disabled:opacity-50'
                    : 'rounded-md bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50'
                }
              >
                {a.label}
              </button>
            ))}
          </div>
        </div>
        {driver.reviewer_note && (
          <div className="mt-4 rounded-md bg-gray-50 px-4 py-3 text-sm">
            <span className="text-gray-500">Reviewer note:</span>{' '}
            <span className="text-gray-900">{driver.reviewer_note}</span>
          </div>
        )}
      </section>

      <div className="grid gap-6 lg:grid-cols-2">
        <LicenceCheck driver={driver} />

        <Card title="Profile">
          <dl className="grid grid-cols-2 gap-x-4 gap-y-3">
            <Field label="Email">{driver.user.email}</Field>
            <Field label="Account status">
              <span className={driver.user.status === 'active' ? '' : 'font-medium text-red-700'}>
                {driver.user.status}
              </span>
            </Field>
            <Field label="ID proof (last 4)">{driver.id_last4 ? `•••• ${driver.id_last4}` : null}</Field>
            <Field label="Rating">
              {driver.stats.rating_avg.toFixed(2)} ({driver.stats.rating_count} ratings)
            </Field>
            <Field label="Rides completed / cancelled">
              {driver.stats.completed_rides} / {driver.stats.cancelled_rides}
            </Field>
            <Field label="Cancellations today">{driver.cancel_count_today}</Field>
            <Field label="Joined (IST)">{formatIST(driver.user.created_at)}</Field>
            <Field label="Approved (IST)">{driver.approved_at ? formatIST(driver.approved_at) : null}</Field>
          </dl>
        </Card>

        <Card
          title="Vehicle"
          action={
            driver.vehicle && (
              <button
                type="button"
                onClick={() => setDialog({ kind: 'vehicle' })}
                className="rounded-md border border-gray-300 px-3 py-1 text-sm text-gray-700 hover:bg-gray-50"
              >
                Edit
              </button>
            )
          }
        >
          {driver.vehicle ? (
            <dl className="grid grid-cols-2 gap-x-4 gap-y-3">
              <Field label="Registration no.">
                <span className="font-mono">{driver.vehicle.reg_number}</span>
              </Field>
              <Field label="Type">{driver.vehicle.vehicle_type}</Field>
              <Field label="Make / model">
                {driver.vehicle.make} {driver.vehicle.model}
              </Field>
              <Field label="Colour">{driver.vehicle.colour}</Field>
              <Field label="Fuel">{driver.vehicle.fuel_type.toUpperCase()}</Field>
              <Field label="Insurance expiry">
                <ExpiryValue value={driver.vehicle.insurance_expiry} />
              </Field>
              <Field label="Permit expiry">
                <ExpiryValue value={driver.vehicle.permit_expiry} />
              </Field>
              <Field label="Fitness expiry">
                <ExpiryValue value={driver.vehicle.fitness_expiry} />
              </Field>
            </dl>
          ) : (
            <p className="text-sm text-gray-500">No vehicle registered.</p>
          )}
        </Card>
      </div>

      <DocumentsSection
        driver={driver}
        busyDocId={busyDocId}
        onApprove={(doc) =>
          docMutation.mutate({ doc, decision: 'approve' }, { onError: (e) => toast.error(errorMessage(e)) })
        }
        onReject={(doc) => setDialog({ kind: 'document', doc })}
        onUrlError={onUrlError}
        onRefresh={refresh}
      />

      {dialog?.kind === 'driver' && (
        <ReasonDialog
          title={dialog.action === 'reject' ? 'Reject driver' : 'Suspend driver'}
          description={
            dialog.action === 'reject'
              ? `${driver.name ?? 'This driver'} will be marked rejected and cannot go online.`
              : `${driver.name ?? 'This driver'} will be taken offline and cannot accept rides until reinstated.`
          }
          confirmLabel={dialog.action === 'reject' ? 'Reject driver' : 'Suspend driver'}
          onConfirm={(note) => driverMutation.mutateAsync({ action: dialog.action, note })}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'document' && (
        <ReasonDialog
          title={`Reject ${DOC_LABEL[dialog.doc.doc_type]}`}
          description="The driver will be asked to upload this document again."
          confirmLabel="Reject document"
          onConfirm={(note) => docMutation.mutateAsync({ doc: dialog.doc, decision: 'reject', note })}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'vehicle' && driver.vehicle && (
        <VehicleEditDialog
          vehicle={driver.vehicle}
          onSave={(patch) => vehicleMutation.mutateAsync(patch)}
          onClose={() => setDialog(null)}
        />
      )}
    </div>
  );
}

function Avatar({ driver, onUrlError }: { driver: Driver; onUrlError: () => void }) {
  const [failed, setFailed] = useState(false);
  const url = driver.selfie_url;
  if (!url || failed) {
    return (
      <div
        className="flex h-16 w-16 shrink-0 items-center justify-center rounded-full bg-gray-200 text-lg font-semibold text-gray-600"
        title={url ? 'Selfie preview unavailable' : 'No selfie'}
      >
        {initials(driver.name)}
      </div>
    );
  }
  return (
    <img
      src={url}
      alt="Selfie"
      onError={() => {
        setFailed(true);
        onUrlError();
      }}
      className="h-16 w-16 shrink-0 rounded-full border border-gray-200 bg-gray-100 object-cover"
    />
  );
}
