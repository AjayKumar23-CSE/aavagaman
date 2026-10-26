import { useState } from 'react';

function isPdf(url: string): boolean {
  try {
    return new URL(url).pathname.toLowerCase().endsWith('.pdf');
  } catch {
    return false;
  }
}

function Placeholder({ text, onRetry }: { text: string; onRetry?: () => void }) {
  return (
    <div className="flex h-40 flex-col items-center justify-center gap-1 rounded-md border border-dashed border-gray-300 bg-gray-50 text-xs text-gray-500">
      <span>{text}</span>
      {onRetry && (
        <button type="button" onClick={onRetry} className="font-medium text-gray-700 underline hover:text-gray-900">
          Reload link
        </button>
      )}
    </div>
  );
}

interface Props {
  url: string | null;
  alt: string;
  /** Called when a signed URL fails to load (it may have expired). */
  onError: () => void;
  /** Re-fetches the driver detail to get fresh signed URLs. */
  onRetry: () => void;
}

/**
 * Signed URLs expire after 5 minutes; mount with `key={url}` so a refetched URL
 * resets the failed state and loads again.
 */
export default function DocPreview({ url, alt, onError, onRetry }: Props) {
  const [failed, setFailed] = useState(false);

  if (!url) return <Placeholder text="No file available" />;

  if (isPdf(url)) {
    return (
      <a
        href={url}
        target="_blank"
        rel="noreferrer"
        className="flex h-40 flex-col items-center justify-center gap-1 rounded-md border border-gray-200 bg-gray-50 text-sm text-gray-700 hover:bg-gray-100"
      >
        <span className="rounded bg-red-600 px-1.5 py-0.5 text-xs font-bold text-white">PDF</span>
        <span className="font-medium underline">Open document</span>
        <span className="text-xs text-gray-400">Opens in a new tab</span>
      </a>
    );
  }

  if (failed) return <Placeholder text="Preview unavailable" onRetry={onRetry} />;

  return (
    <a href={url} target="_blank" rel="noreferrer" className="block" title="Open full size">
      <img
        src={url}
        alt={alt}
        loading="lazy"
        onError={() => {
          setFailed(true);
          onError();
        }}
        className="h-40 w-full rounded-md border border-gray-200 bg-gray-100 object-contain"
      />
    </a>
  );
}
