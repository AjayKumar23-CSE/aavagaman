import StatusBadge from '../../components/StatusBadge';
import {
  DOC_LABEL,
  DOC_TYPES,
  MANDATORY_DOC_TYPES,
  type DocType,
  type DocumentHistoryItem,
  type DriverDetail,
} from '../../lib/drivers';
import { formatDay, formatIST, isExpired } from '../../lib/time';
import DocPreview from './DocPreview';

interface Props {
  driver: DriverDetail;
  busyDocId: string | null;
  onApprove: (doc: DocumentHistoryItem) => void;
  onReject: (doc: DocumentHistoryItem) => void;
  onUrlError: () => void;
  onRefresh: () => void;
}

function Expiry({ value }: { value: string | null }) {
  if (!value) return null;
  const expired = isExpired(value);
  return (
    <span className={expired ? 'font-medium text-red-700' : 'text-gray-600'}>
      Expires {formatDay(value)}
      {expired && (
        <span className="ml-1.5">
          <StatusBadge status="expired" />
        </span>
      )}
    </span>
  );
}

function DocumentCard({
  type,
  uploads,
  busy,
  onApprove,
  onReject,
  onUrlError,
  onRefresh,
}: {
  type: DocType;
  uploads: DocumentHistoryItem[];
  busy: boolean;
} & Omit<Props, 'driver' | 'busyDocId'>) {
  const [current, ...older] = uploads;
  const mandatory = MANDATORY_DOC_TYPES.includes(type);

  return (
    <div data-doc-type={type} className="flex flex-col rounded-lg border border-gray-200 bg-white p-4">
      <div className="mb-2 flex items-start justify-between gap-2">
        <div>
          <h3 className="text-sm font-semibold text-gray-900">{DOC_LABEL[type]}</h3>
          {!mandatory && <span className="text-xs text-gray-400">Optional</span>}
        </div>
        {current ? <StatusBadge status={current.status} /> : mandatory && <StatusBadge status="missing" />}
      </div>

      {!current ? (
        <div className="flex h-40 items-center justify-center rounded-md border border-dashed border-gray-300 bg-gray-50 text-xs text-gray-500">
          {mandatory ? 'Not uploaded — required' : 'Not uploaded'}
        </div>
      ) : (
        <>
          <div className="mb-3 min-h-8 space-y-0.5 text-xs">
            <div className="text-gray-500">Uploaded {formatIST(current.uploaded_at)} IST</div>
            <div>
              <Expiry value={current.expiry} />
            </div>
            {current.reviewer_note && (
              <div className="text-gray-700">
                <span className="text-gray-500">Note:</span> {current.reviewer_note}
              </div>
            )}
          </div>

          <DocPreview
            key={current.view_url ?? current.id}
            url={current.view_url}
            alt={DOC_LABEL[type]}
            onError={onUrlError}
            onRetry={onRefresh}
          />

          <div className="mt-auto flex gap-2 pt-3">
            {current.status !== 'approved' && (
              <button
                type="button"
                disabled={busy}
                onClick={() => onApprove(current)}
                className="flex-1 rounded-md bg-green-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50"
              >
                Approve
              </button>
            )}
            {current.status !== 'rejected' && (
              <button
                type="button"
                disabled={busy}
                onClick={() => onReject(current)}
                className="flex-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-red-50 disabled:opacity-50"
              >
                Reject
              </button>
            )}
          </div>

          {older.length > 0 && (
            <details className="mt-3 text-xs">
              <summary className="cursor-pointer text-gray-600 hover:text-gray-900">
                {older.length} older upload{older.length > 1 ? 's' : ''}
              </summary>
              <ul className="mt-2 divide-y divide-gray-100 rounded-md border border-gray-100">
                {older.map((d) => (
                  <li key={d.id} className="space-y-0.5 px-3 py-2">
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-gray-600">{formatIST(d.uploaded_at)}</span>
                      <StatusBadge status={d.status} />
                    </div>
                    <Expiry value={d.expiry} />
                    {d.reviewer_note && <div className="text-gray-700">Note: {d.reviewer_note}</div>}
                    {d.view_url && (
                      <a href={d.view_url} target="_blank" rel="noreferrer" className="text-gray-700 underline">
                        View file
                      </a>
                    )}
                  </li>
                ))}
              </ul>
            </details>
          )}
        </>
      )}
    </div>
  );
}

function Banner({ tone, label, text }: { tone: 'red' | 'amber'; label: string; text: string }) {
  const colour =
    tone === 'red' ? 'border-red-200 bg-red-50 text-red-800' : 'border-amber-200 bg-amber-50 text-amber-800';
  return (
    <div className={`rounded-md border px-4 py-3 text-sm ${colour}`}>
      <span className="font-medium">{label}</span> {text}
    </div>
  );
}

export default function DocumentsSection({ driver, busyDocId, ...handlers }: Props) {
  const byType = new Map<DocType, DocumentHistoryItem[]>();
  for (const d of driver.document_history) {
    byType.set(d.doc_type, [...(byType.get(d.doc_type) ?? []), d]);
  }
  // The API's missing_documents also counts rejected uploads; split them so the admin sees why.
  const current = (t: DocType) => byType.get(t)?.[0];
  const labels = (types: DocType[]) => types.map((t) => DOC_LABEL[t]).join(', ');
  const notUploaded = MANDATORY_DOC_TYPES.filter((t) => !current(t));
  const rejected = MANDATORY_DOC_TYPES.filter((t) => current(t)?.status === 'rejected');
  const awaitingReview = MANDATORY_DOC_TYPES.filter((t) => current(t)?.status === 'pending');
  const expired = DOC_TYPES.filter((t) => isExpired(current(t)?.expiry));

  return (
    <section className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-gray-900">Documents</h2>
        <button
          type="button"
          onClick={handlers.onRefresh}
          className="rounded-md border border-gray-300 bg-white px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-50"
          title="Signed links expire after 5 minutes"
        >
          Refresh links
        </button>
      </div>

      {notUploaded.length > 0 && <Banner tone="red" label="Missing mandatory documents:" text={labels(notUploaded)} />}
      {rejected.length > 0 && <Banner tone="red" label="Rejected, awaiting re-upload:" text={labels(rejected)} />}
      {expired.length > 0 && <Banner tone="red" label="Expired:" text={labels(expired)} />}
      {awaitingReview.length > 0 && <Banner tone="amber" label="Awaiting review:" text={labels(awaitingReview)} />}

      <div className="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
        {DOC_TYPES.map((t) => {
          const uploads = byType.get(t) ?? [];
          return (
            <DocumentCard
              key={t}
              type={t}
              uploads={uploads}
              busy={busyDocId !== null && busyDocId === uploads[0]?.id}
              {...handlers}
            />
          );
        })}
      </div>
    </section>
  );
}
