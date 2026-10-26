import { errorMessage } from '../lib/api';

interface Props {
  error: unknown;
  onRetry?: () => void;
}

export default function ErrorBanner({ error, onRetry }: Props) {
  return (
    <div role="alert" className="flex items-center justify-between rounded-md bg-red-50 px-4 py-3 text-sm text-red-700">
      <span>{errorMessage(error)}</span>
      {onRetry && (
        <button type="button" onClick={onRetry} className="font-medium underline">
          Retry
        </button>
      )}
    </div>
  );
}
