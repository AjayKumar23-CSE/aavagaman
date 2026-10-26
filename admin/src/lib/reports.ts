import { api, downloadFile, qs } from './api';

export interface DailyRow {
  day: string;
  requested: number;
  completed: number;
  cancelled: number;
  no_driver: number;
  paid_rides: number;
  revenue: number;
  gross_fares: number;
  gst: number;
  commission: number;
  cash: number;
  online: number;
}

export interface DailyReport {
  from: string;
  to: string;
  data: DailyRow[];
}

/** Per IST day, both ends inclusive, at most a year. */
export function getDailyReport(from: string, to: string): Promise<DailyReport> {
  return api(`/v1/admin/reports/daily${qs({ from, to })}`);
}

export function downloadDailyCsv(from: string, to: string): Promise<void> {
  return downloadFile(`/v1/admin/reports/daily${qs({ from, to, format: 'csv' })}`, `daily-${from}-to-${to}.csv`);
}
