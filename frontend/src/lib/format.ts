import { MIST_PER_SUI } from './constants';

export function mistToSui(mist: bigint): string {
  const whole = mist / MIST_PER_SUI;
  const frac = mist % MIST_PER_SUI;
  if (frac === 0n) return whole.toString();
  const fracStr = frac.toString().padStart(9, '0').replace(/0+$/, '');
  return `${whole}.${fracStr}`;
}

export function suiToMist(sui: string): bigint {
  const trimmed = sui.trim();
  if (!trimmed || !/^-?\d+(\.\d+)?$/.test(trimmed)) {
    throw new Error(`Invalid SUI amount: "${sui}"`);
  }
  const parts = trimmed.split('.');
  const whole = BigInt(parts[0] || '0') * MIST_PER_SUI;
  if (!parts[1]) return whole;
  const fracStr = parts[1].padEnd(9, '0').slice(0, 9);
  return whole + BigInt(fracStr);
}

export function truncateAddress(addr: string, chars = 6): string {
  if (addr.length <= chars * 2 + 2) return addr;
  return `${addr.slice(0, chars + 2)}...${addr.slice(-chars)}`;
}

export function formatTimestamp(ms: number): string {
  return new Date(ms).toLocaleString();
}

export function formatCountdown(targetMs: number): string {
  const diff = targetMs - Date.now();
  if (diff <= 0) return 'Expired';

  const days = Math.floor(diff / 86_400_000);
  const hours = Math.floor((diff % 86_400_000) / 3_600_000);
  const mins = Math.floor((diff % 3_600_000) / 60_000);

  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${mins}m`;
  const secs = Math.floor((diff % 60_000) / 1000);
  return `${mins}m ${secs}s`;
}

export function bpsToPercent(bps: number): string {
  return `${(bps / 100).toFixed(1)}%`;
}

export function timeAgo(ms: number): string {
  const diff = Date.now() - ms;
  const mins = Math.floor(diff / 60_000);
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

export function parseErrorCode(errorMsg: string): number | null {
  const match = errorMsg.match(/MoveAbort.*?(\d+)\)?\s*$/);
  if (match) return parseInt(match[1], 10);
  const match2 = errorMsg.match(/abort_code: (\d+)/);
  if (match2) return parseInt(match2[1], 10);
  return null;
}
