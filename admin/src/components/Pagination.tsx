interface Props {
  page: number;
  limit: number;
  total: number;
  onPage: (page: number) => void;
}

export default function Pagination({ page, limit, total, onPage }: Props) {
  const pages = Math.max(1, Math.ceil(total / limit));
  const from = total === 0 ? 0 : (page - 1) * limit + 1;
  const to = Math.min(page * limit, total);
  return (
    <div className="flex items-center justify-between text-sm text-gray-600">
      <span>{total > 0 ? `Showing ${from}–${to} of ${total}` : ''}</span>
      <div className="flex items-center gap-2">
        <button
          type="button"
          disabled={page <= 1}
          onClick={() => onPage(page - 1)}
          className="rounded-md border border-gray-300 bg-white px-3 py-1.5 hover:bg-gray-50 disabled:opacity-40"
        >
          Previous
        </button>
        <span>
          Page {page} of {pages}
        </span>
        <button
          type="button"
          disabled={page >= pages}
          onClick={() => onPage(page + 1)}
          className="rounded-md border border-gray-300 bg-white px-3 py-1.5 hover:bg-gray-50 disabled:opacity-40"
        >
          Next
        </button>
      </div>
    </div>
  );
}
